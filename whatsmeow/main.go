// Sidecar HTTP que expone sesiones de WhatsApp (whatsmeow) a Caseo. Cada
// gestor vincula su propio número en una sesión identificada por un id que
// elige Caseo.
//
// Endpoints (todos salvo /health exigen "Authorization: Bearer $WHATSMEOW_TOKEN"):
//
//	GET  /health                 -> 200 si el proceso está vivo
//	POST /sessions/{id}/connect  -> crea la sesión si no existe y arranca la vinculación
//	GET  /sessions/{id}/status   -> {"connected":bool,"logged_in":bool,"jid":string}
//	GET  /sessions/{id}/qr       -> {"code":string} mientras se espera la vinculación; 204 si no hay código
//	GET  /sessions/{id}/qr.png   -> el mismo código como imagen PNG
//	POST /sessions/{id}/send     -> {"to":"34600111222","text":"hola"} -> {"id":string,"timestamp":string}
//	POST /sessions/{id}/logout   -> desvincula el número y borra la sesión
//
// Los mensajes de cada sesión se reenvían como JSON a WEBHOOK_URL, con el id de la sesión.
package main

import (
	"bytes"
	"context"
	"crypto/subtle"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"math/rand/v2"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	_ "github.com/lib/pq"
	"github.com/skip2/go-qrcode"
	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/store"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
	"google.golang.org/protobuf/proto"
)

var sessionID = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

// limits frenan los envíos de cada número para reducir el riesgo de baneo (#22).
type limits struct {
	perHour  int
	minDelay time.Duration
	maxDelay time.Duration
}

type server struct {
	db         *sql.DB
	container  *sqlstore.Container
	token      string
	webhookURL string
	limits     limits

	mu       sync.Mutex
	sessions map[string]*session
}

type session struct {
	id     string
	client *whatsmeow.Client

	mu   sync.Mutex
	qr   string
	sent []time.Time

	// send serializa los envíos de la sesión para aplicar el retardo entre mensajes.
	send sync.Mutex
}

func main() {
	ctx := context.Background()
	dsn := mustEnv("DATABASE_URL")

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		log.Fatalf("db: %v", err)
	}
	container := sqlstore.NewWithDB(db, "postgres", waLog.Stdout("store", "INFO", false))
	if err := container.Upgrade(ctx); err != nil {
		log.Fatalf("store: %v", err)
	}
	// Qué dispositivo de whatsmeow pertenece a cada sesión de Caseo.
	if _, err := db.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS caseo_whatsmeow_sessions (
		session_id text PRIMARY KEY,
		jid text NOT NULL
	)`); err != nil {
		log.Fatalf("sesiones: %v", err)
	}

	s := &server{
		db:         db,
		container:  container,
		token:      mustEnv("WHATSMEOW_TOKEN"),
		webhookURL: os.Getenv("WEBHOOK_URL"),
		sessions:   map[string]*session{},
		// ponytail: configurables por entorno para self-hosted; el plan cloud no los expone.
		limits: limits{
			perHour:  envInt("SEND_MAX_PER_HOUR", 60),
			minDelay: time.Duration(envInt("SEND_DELAY_MIN_MS", 1500)) * time.Millisecond,
			maxDelay: time.Duration(envInt("SEND_DELAY_MAX_MS", 4000)) * time.Millisecond,
		},
	}
	s.restore(ctx)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	mux.HandleFunc("POST /sessions/{id}/connect", s.auth(s.connect))
	mux.HandleFunc("GET /sessions/{id}/status", s.auth(s.status))
	mux.HandleFunc("GET /sessions/{id}/qr", s.auth(s.qrCode))
	mux.HandleFunc("GET /sessions/{id}/qr.png", s.auth(s.qrImage))
	mux.HandleFunc("POST /sessions/{id}/send", s.auth(s.sendMessage))
	mux.HandleFunc("POST /sessions/{id}/logout", s.auth(s.logout))

	addr := envOr("LISTEN_ADDR", ":8080")
	log.Printf("whatsmeow sidecar escuchando en %s (%d sesiones)", addr, len(s.sessions))
	log.Fatal(http.ListenAndServe(addr, mux))
}

// restore reconecta las sesiones ya vinculadas al arrancar.
func (s *server) restore(ctx context.Context) {
	rows, err := s.db.QueryContext(ctx, `SELECT session_id, jid FROM caseo_whatsmeow_sessions`)
	if err != nil {
		log.Fatalf("sesiones: %v", err)
	}
	defer rows.Close()
	for rows.Next() {
		var id, raw string
		if err := rows.Scan(&id, &raw); err != nil {
			log.Fatalf("sesiones: %v", err)
		}
		jid, err := types.ParseJID(raw)
		if err != nil {
			log.Printf("sesión %s: jid no válido", id)
			continue
		}
		device, err := s.container.GetDevice(ctx, jid)
		if err != nil || device == nil {
			log.Printf("sesión %s: dispositivo no encontrado, hay que volver a vincular", id)
			continue
		}
		sess := s.newSession(id, device)
		if err := sess.client.Connect(); err != nil {
			log.Printf("sesión %s: conectar: %v", id, err)
		}
	}
}

func (s *server) newSession(id string, device *store.Device) *session {
	sess := &session{id: id, client: whatsmeow.NewClient(device, waLog.Stdout("client:"+id, "INFO", false))}
	sess.client.AddEventHandler(func(evt any) { s.handleEvent(sess, evt) })
	s.mu.Lock()
	s.sessions[id] = sess
	s.mu.Unlock()
	return sess
}

func (s *server) session(id string) *session {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.sessions[id]
}

// pair arranca la vinculación por QR de una sesión sin número.
func (s *server) pair(sess *session) error {
	qrChan, err := sess.client.GetQRChannel(context.Background())
	if err != nil {
		return err
	}
	if err := sess.client.Connect(); err != nil {
		return err
	}
	go func() {
		for item := range qrChan {
			sess.mu.Lock()
			if item.Event == whatsmeow.QRChannelEventCode {
				sess.qr = item.Code
			} else {
				sess.qr = ""
				log.Printf("sesión %s: vinculación %s", sess.id, item.Event)
			}
			sess.mu.Unlock()
		}
		// Los QR caducan: si se agotan sin vincular, la sesión se descarta y
		// Caseo vuelve a pedir /connect cuando el gestor lo intente de nuevo.
		if sess.client.Store.ID == nil {
			sess.client.Disconnect()
			s.mu.Lock()
			delete(s.sessions, sess.id)
			s.mu.Unlock()
		}
	}()
	return nil
}

func (s *server) handleEvent(sess *session, evt any) {
	switch v := evt.(type) {
	case *events.PairSuccess:
		if _, err := s.db.Exec(
			`INSERT INTO caseo_whatsmeow_sessions (session_id, jid) VALUES ($1, $2)
			 ON CONFLICT (session_id) DO UPDATE SET jid = EXCLUDED.jid`,
			sess.id, v.ID.String(),
		); err != nil {
			log.Printf("sesión %s: guardar vínculo: %v", sess.id, err)
		}
	case *events.Message:
		s.forward(sess, v)
	case *events.LoggedOut:
		log.Printf("sesión %s: cerrada desde el móvil", sess.id)
		s.drop(sess)
	}
}

// drop desconecta la sesión y olvida su vínculo; el gestor tendrá que volver a vincular.
func (s *server) drop(sess *session) {
	sess.client.Disconnect()
	if _, err := s.db.Exec(`DELETE FROM caseo_whatsmeow_sessions WHERE session_id = $1`, sess.id); err != nil {
		log.Printf("sesión %s: borrar vínculo: %v", sess.id, err)
	}
	s.mu.Lock()
	delete(s.sessions, sess.id)
	s.mu.Unlock()
}

type incoming struct {
	Session   string    `json:"session"`
	ID        string    `json:"id"`
	From      string    `json:"from"`
	Chat      string    `json:"chat"`
	PushName  string    `json:"push_name"`
	FromMe    bool      `json:"from_me"`
	Type      string    `json:"type"`
	Text      string    `json:"text"`
	Timestamp time.Time `json:"timestamp"`
}

func (s *server) forward(sess *session, m *events.Message) {
	if s.webhookURL == "" {
		return
	}
	chat, ok := s.phoneChat(sess, m)
	if !ok {
		return
	}
	kind, text := content(m.Message)
	body, _ := json.Marshal(incoming{
		Session:   sess.id,
		ID:        m.Info.ID,
		From:      m.Info.Sender.User,
		Chat:      chat.User,
		PushName:  m.Info.PushName,
		FromMe:    m.Info.IsFromMe,
		Type:      kind,
		Text:      text,
		Timestamp: m.Info.Timestamp,
	})
	req, err := http.NewRequest(http.MethodPost, s.webhookURL, bytes.NewReader(body))
	if err != nil {
		log.Printf("webhook: %v", err)
		return
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.token)
	// ponytail: sin reintentos ni cola; si core está caído el mensaje se pierde. Añadir cola persistente si importa.
	resp, err := (&http.Client{Timeout: 10 * time.Second}).Do(req)
	if err != nil {
		log.Printf("webhook: %v", err)
		return
	}
	resp.Body.Close()
}

// phoneChat devuelve el chat individual identificado por número. WhatsApp
// identifica cada vez más chats por un LID oculto; se traduce al número con la
// dirección alternativa del mensaje o con la tabla de LIDs de la sesión. Los
// grupos, los estados y los LID sin número conocido se descartan.
func (s *server) phoneChat(sess *session, m *events.Message) (types.JID, bool) {
	chat := m.Info.Chat
	switch chat.Server {
	case types.DefaultUserServer:
		return chat, true
	case types.HiddenUserServer:
		for _, alt := range []types.JID{m.Info.SenderAlt, m.Info.RecipientAlt} {
			if alt.Server == types.DefaultUserServer {
				return alt.ToNonAD(), true
			}
		}
		pn, err := sess.client.Store.LIDs.GetPNForLID(context.Background(), chat)
		if err == nil && pn.Server == types.DefaultUserServer {
			return pn, true
		}
		log.Printf("sesión %s: chat %s sin número conocido, se ignora", sess.id, chat)
	}
	return types.JID{}, false
}

// content devuelve el tipo del mensaje y su texto (o el pie de foto).
func content(m *waE2E.Message) (string, string) {
	switch {
	case m.GetConversation() != "":
		return "text", m.GetConversation()
	case m.GetExtendedTextMessage() != nil:
		return "text", m.GetExtendedTextMessage().GetText()
	case m.GetImageMessage() != nil:
		return "image", m.GetImageMessage().GetCaption()
	case m.GetVideoMessage() != nil:
		return "video", m.GetVideoMessage().GetCaption()
	case m.GetAudioMessage() != nil:
		return "audio", ""
	case m.GetDocumentMessage() != nil:
		return "document", m.GetDocumentMessage().GetFileName()
	case m.GetLocationMessage() != nil:
		return "location", ""
	default:
		return "other", ""
	}
}

func (s *server) connect(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !sessionID.MatchString(id) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "id de sesión no válido"})
		return
	}
	if s.session(id) == nil {
		sess := s.newSession(id, s.container.NewDevice())
		if err := s.pair(sess); err != nil {
			s.mu.Lock()
			delete(s.sessions, id)
			s.mu.Unlock()
			writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
			return
		}
	}
	s.status(w, r)
}

func (s *server) status(w http.ResponseWriter, r *http.Request) {
	sess := s.session(r.PathValue("id"))
	if sess == nil {
		writeJSON(w, http.StatusOK, map[string]any{"connected": false, "logged_in": false, "jid": ""})
		return
	}
	jid := ""
	if sess.client.Store.ID != nil {
		jid = sess.client.Store.ID.User
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"connected": sess.client.IsConnected(),
		"logged_in": sess.client.IsLoggedIn(),
		"jid":       jid,
	})
}

func (s *server) currentQR(r *http.Request) string {
	sess := s.session(r.PathValue("id"))
	if sess == nil {
		return ""
	}
	sess.mu.Lock()
	defer sess.mu.Unlock()
	return sess.qr
}

func (s *server) qrCode(w http.ResponseWriter, r *http.Request) {
	code := s.currentQR(r)
	if code == "" {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"code": code})
}

func (s *server) qrImage(w http.ResponseWriter, r *http.Request) {
	code := s.currentQR(r)
	if code == "" {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	png, err := qrcode.Encode(code, qrcode.Medium, 320)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	w.Header().Set("Content-Type", "image/png")
	w.Header().Set("Cache-Control", "no-store")
	_, _ = w.Write(png)
}

func (s *server) sendMessage(w http.ResponseWriter, r *http.Request) {
	sess := s.session(r.PathValue("id"))
	var in struct {
		To   string `json:"to"`
		Text string `json:"text"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&in); err != nil || in.Text == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "se requieren 'to' y 'text'"})
		return
	}
	to := strings.TrimLeft(in.To, "+")
	if to == "" || strings.Trim(to, "0123456789") != "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "'to' debe ser un número en formato internacional"})
		return
	}
	if sess == nil || !sess.client.IsLoggedIn() {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "número no vinculado"})
		return
	}
	if !sess.allow(s.limits.perHour) {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{"error": "límite de envíos por hora alcanzado"})
		return
	}

	sess.send.Lock()
	defer sess.send.Unlock()
	time.Sleep(s.limits.delay())
	resp, err := sess.client.SendMessage(r.Context(), types.NewJID(to, types.DefaultUserServer), &waE2E.Message{
		Conversation: proto.String(in.Text),
	})
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"id": resp.ID, "timestamp": resp.Timestamp})
}

// allow cuenta el envío si la sesión no ha llegado al máximo de la última hora.
func (sess *session) allow(perHour int) bool {
	sess.mu.Lock()
	defer sess.mu.Unlock()
	cutoff := time.Now().Add(-time.Hour)
	recent := sess.sent[:0]
	for _, t := range sess.sent {
		if t.After(cutoff) {
			recent = append(recent, t)
		}
	}
	sess.sent = recent
	if len(sess.sent) >= perHour {
		return false
	}
	sess.sent = append(sess.sent, time.Now())
	return true
}

// delay es un retardo aleatorio entre mensajes, para no enviar a ritmo de máquina.
func (l limits) delay() time.Duration {
	if l.maxDelay <= l.minDelay {
		return l.minDelay
	}
	return l.minDelay + rand.N(l.maxDelay-l.minDelay)
}

func (s *server) logout(w http.ResponseWriter, r *http.Request) {
	sess := s.session(r.PathValue("id"))
	if sess == nil {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if err := sess.client.Logout(r.Context()); err != nil && !errors.Is(err, whatsmeow.ErrNotLoggedIn) {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}
	s.drop(sess)
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) auth(next http.HandlerFunc) http.HandlerFunc {
	want := []byte("Bearer " + s.token)
	return func(w http.ResponseWriter, r *http.Request) {
		if subtle.ConstantTimeCompare([]byte(r.Header.Get("Authorization")), want) != 1 {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("falta la variable de entorno %s", key)
	}
	return v
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	if n, err := strconv.Atoi(os.Getenv(key)); err == nil && n >= 0 {
		return n
	}
	return def
}
