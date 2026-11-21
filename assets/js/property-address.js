import accessibleAutocomplete from "accessible-autocomplete";
import { circleMarker, map, tileLayer } from "leaflet";

const addressFields = ["street", "municipality", "postal_code", "province"];
const coordinateFields = ["latitude", "longitude"];
const fields = [...addressFields, ...coordinateFields];

function addressLabel(address) {
  const municipality =
    address.municipality === address.province
      ? address.municipality
      : `${address.municipality}, ${address.province}`;
  return [address.street, address.postal_code, municipality].filter(Boolean).join(" · ");
}

function escapeSuggestion(text) {
  return text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

export const PropertyAddress = {
  mounted() {
    this.form = this.el.closest("form");
    this.mapElement = this.el.querySelector("[data-address-map]");
    this.status = this.el.querySelector("[data-address-status]");
    this.listeners = new AbortController();
    this.results = new Map();

    accessibleAutocomplete({
      element: this.el.querySelector("[data-address-autocomplete]"),
      id: "property-address-query",
      cssNamespace: "property-address-autocomplete",
      inputClasses: "input w-full",
      minLength: 4,
      confirmOnBlur: false,
      placeholder: "Ej. Calle Mayor 12, Madrid",
      source: (query, populate) => this.search(query, populate),
      onConfirm: (label) => this.selectAddress(this.results.get(label)),
      templates: { suggestion: escapeSuggestion },
      tNoResults: () => "No se encontraron direcciones",
      tStatusNoResults: () => "No se encontraron direcciones",
      tStatusQueryTooShort: (length) => `Escribe al menos ${length} caracteres.`,
      tStatusSelectedOption: (option, total, index) => `${option}, ${index + 1} de ${total}`,
      tStatusResults: (total, selected) => `${total} direcciones. ${selected}`,
      tAssistiveHint: () =>
        "Usa las flechas para recorrer los resultados y Enter para seleccionar.",
    });

    const input = this.el.querySelector("#property-address-query");
    input.maxLength = 160;
    const options = { signal: this.listeners.signal };

    input.addEventListener(
      "keydown",
      (event) => {
        if (event.key === "Enter") event.preventDefault();
      },
      options,
    );

    input.addEventListener(
      "input",
      (event) => {
        event.stopPropagation();
        if (input.value.trim().length < 4) {
          this.cancelSearch();
          this.setStatus("");
        }
      },
      options,
    );

    this.form.addEventListener(
      "input",
      (event) => {
        if (this.selecting || !addressFields.some((name) => this.field(name) === event.target))
          return;

        for (const name of coordinateFields) this.field(name).value = "";
        this.mapElement.hidden = true;
      },
      options,
    );

    this.showSavedLocation();
  },

  field(name) {
    return this.form.elements.namedItem(`property[${name}]`);
  },

  search(query, populate) {
    this.cancelSearch();
    this.results = new Map();
    const term = query.trim();
    if (term.length < 4 || term.length > 160) {
      this.setStatus("");
      populate([]);
      return;
    }

    this.setStatus("Buscando direcciones…");
    const request = new AbortController();
    this.request = request;
    this.timer = setTimeout(async () => {
      try {
        const params = new URLSearchParams({ address_query: term });
        const response = await fetch(`${this.el.dataset.searchUrl}?${params}`, {
          signal: request.signal,
        });
        if (!response.ok) throw new Error("Address lookup failed");

        const { addresses } = await response.json();
        if (request.signal.aborted) return;

        this.results = new Map(addresses.map((address) => [addressLabel(address), address]));
        this.setStatus("");
        populate([...this.results.keys()]);
      } catch {
        if (request.signal.aborted) return;
        this.setStatus("La búsqueda no está disponible. Puedes introducir la dirección a mano.");
        populate([]);
      }
    }, 300);
  },

  cancelSearch() {
    clearTimeout(this.timer);
    this.request?.abort();
  },

  setStatus(message) {
    this.status.textContent = message;
    this.status.hidden = !message;
  },

  selectAddress(address) {
    if (!address) return;

    for (const name of fields) this.field(name).value = address[name] ?? "";
    this.selecting = true;
    this.field("street").dispatchEvent(new Event("input", { bubbles: true }));
    this.selecting = false;
    this.showSavedLocation();

    if (!address.postal_code) {
      this.form.querySelector("#property-address-fields").open = true;
      this.setStatus("Completa el código postal.");
    } else {
      this.setStatus("");
    }
  },

  showSavedLocation() {
    const values = coordinateFields.map((name) => this.field(name).value);
    if (values.some((value) => value === "")) return;

    const position = values.map(Number);
    if (!position.every(Number.isFinite)) return;

    this.mapElement.hidden = false;
    if (!this.map) {
      this.map = map(this.mapElement, { scrollWheelZoom: false });
      tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 19,
        referrerPolicy: "strict-origin-when-cross-origin",
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      }).addTo(this.map);
      this.marker = circleMarker(position, {
        radius: 8,
        color: "#ffffff",
        weight: 3,
        fillColor: "#245580",
        fillOpacity: 1,
      }).addTo(this.map);
    }

    this.map.invalidateSize();
    this.map.setView(position, 17);
    this.marker.setLatLng(position);
  },

  destroyed() {
    this.cancelSearch();
    this.listeners.abort();
    this.map?.remove();
  },
};
