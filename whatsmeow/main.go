// Sidecar HTTP que expone una sesión de WhatsApp (whatsmeow) a Caseo.
//
// Endpoints (todos salvo /health exigen "Authorization: Bearer $WHATSMEOW_TOKEN"):
//
//	GET  /health  -> 200 si el proceso está vivo
//	GET  /status  -> {"connected":bool,"logged_in":bool,"jid":string}
//	GET  /qr      -> {"code":string} mientras se espera la vinculación; 204 si ya está vinculado
//	POST /send    -> {"to":"34600111222","text":"hola"} -> {"id":string,"timestamp":string}
//	POST /logout  -> desvincula el número
//
// Los mensajes entrantes se reenvían como JSON a WEBHOOK_URL (si está definido).
package main

import (
	"bytes"
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	_ "github.com/lib/pq"
	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
	"google.golang.org/protobuf/proto"
)

type server struct {
	client     *whatsmeow.Client
	token      string
	webhookURL string

	mu sync.Mutex
	qr string
}

func main() {
	ctx := context.Background()
	dsn := mustEnv("DATABASE_URL")
	token := mustEnv("WHATSMEOW_TOKEN")
	addr := envOr("LISTEN_ADDR", ":8080")

	container, err := sqlstore.New(ctx, "postgres", dsn, waLog.Stdout("store", "INFO", false))
	if err != nil {
		log.Fatalf("store: %v", err)
	}
	device, err := container.GetFirstDevice(ctx)
	if err != nil {
		log.Fatalf("device: %v", err)
	}

	s := &server{
		client:     whatsmeow.NewClient(device, waLog.Stdout("client", "INFO", false)),
		token:      token,
		webhookURL: os.Getenv("WEBHOOK_URL"),
	}
	s.client.AddEventHandler(s.handleEvent)
	if err := s.connect(); err != nil {
		log.Fatalf("connect: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	mux.HandleFunc("GET /status", s.auth(s.status))
	mux.HandleFunc("GET /qr", s.auth(s.qrCode))
	mux.HandleFunc("POST /send", s.auth(s.send))
	mux.HandleFunc("POST /logout", s.auth(s.logout))

	log.Printf("whatsmeow sidecar escuchando en %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}

// connect conecta la sesión existente o, si no hay ninguna, arranca la vinculación por QR.
func (s *server) connect() error {
	if s.client.Store.ID != nil {
		return s.client.Connect()
	}
	qrChan, err := s.client.GetQRChannel(context.Background())
	if err != nil {
		return err
	}
	if err := s.client.Connect(); err != nil {
		return err
	}
	go func() {
		for item := range qrChan {
			s.mu.Lock()
			if item.Event == whatsmeow.QRChannelEventCode {
				s.qr = item.Code
			} else {
				s.qr = ""
				log.Printf("vinculación: %s", item.Event)
			}
			s.mu.Unlock()
		}
		// Los QR caducan: si se agotan sin vincular, se pide una tanda nueva.
		if s.client.Store.ID == nil {
			s.client.Disconnect()
			time.Sleep(5 * time.Second)
			if err := s.connect(); err != nil {
				log.Printf("reiniciar vinculación: %v", err)
			}
		}
	}()
	return nil
}

func (s *server) handleEvent(evt any) {
	switch v := evt.(type) {
	case *events.Message:
		s.forward(v)
	case *events.LoggedOut:
		log.Print("sesión cerrada desde el móvil; volviendo a modo vinculación")
		s.client.Disconnect()
		go func() {
			if err := s.connect(); err != nil {
				log.Printf("reconectar: %v", err)
			}
		}()
	}
}

type incoming struct {
	ID        string    `json:"id"`
	From      string    `json:"from"`
	Chat      string    `json:"chat"`
	PushName  string    `json:"push_name"`
	FromMe    bool      `json:"from_me"`
	Text      string    `json:"text"`
	Timestamp time.Time `json:"timestamp"`
}

func (s *server) forward(m *events.Message) {
	if s.webhookURL == "" {
		return
	}
	text := m.Message.GetConversation()
	if text == "" {
		text = m.Message.GetExtendedTextMessage().GetText()
	}
	body, _ := json.Marshal(incoming{
		ID:        m.Info.ID,
		From:      m.Info.Sender.User,
		Chat:      m.Info.Chat.String(),
		PushName:  m.Info.PushName,
		FromMe:    m.Info.IsFromMe,
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

func (s *server) status(w http.ResponseWriter, _ *http.Request) {
	jid := ""
	if s.client.Store.ID != nil {
		jid = s.client.Store.ID.User
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"connected": s.client.IsConnected(),
		"logged_in": s.client.IsLoggedIn(),
		"jid":       jid,
	})
}

func (s *server) qrCode(w http.ResponseWriter, _ *http.Request) {
	s.mu.Lock()
	code := s.qr
	s.mu.Unlock()
	if code == "" {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"code": code})
}

func (s *server) send(w http.ResponseWriter, r *http.Request) {
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
	if !s.client.IsLoggedIn() {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "número no vinculado"})
		return
	}
	// ponytail: sin límite de envío todavía; los límites y retardos de #22 van aquí.
	resp, err := s.client.SendMessage(r.Context(), types.NewJID(to, types.DefaultUserServer), &waE2E.Message{
		Conversation: proto.String(in.Text),
	})
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"id": resp.ID, "timestamp": resp.Timestamp})
}

func (s *server) logout(w http.ResponseWriter, r *http.Request) {
	if err := s.client.Logout(r.Context()); err != nil && !errors.Is(err, whatsmeow.ErrNotLoggedIn) {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}
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
