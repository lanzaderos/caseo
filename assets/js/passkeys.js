function decode(value) {
  return Uint8Array.from(atob(value.replace(/-/g, "+").replace(/_/g, "/")), (byte) =>
    byte.charCodeAt(0),
  );
}

function encode(buffer) {
  const bytes = Array.from(new Uint8Array(buffer), (byte) => String.fromCharCode(byte));
  return btoa(bytes.join("")).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function post(url, csrfToken, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json", "x-csrf-token": csrfToken },
    body: JSON.stringify(body),
  });

  if (response.redirected) return { location: response.url };
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || "The passkey request failed.");
  return data;
}

async function createPasskey(publicKey) {
  publicKey.user.id = decode(publicKey.user.id);
  for (const credential of publicKey.excludeCredentials) credential.id = decode(credential.id);

  const { rawId, response } = await navigator.credentials.create({ publicKey });
  return {
    credentialId: encode(rawId),
    clientDataJSON: encode(response.clientDataJSON),
    attestationObject: encode(response.attestationObject),
  };
}

async function getPasskey(publicKey) {
  const { rawId, response } = await navigator.credentials.get({ publicKey });
  return {
    credentialId: encode(rawId),
    clientDataJSON: encode(response.clientDataJSON),
    authenticatorData: encode(response.authenticatorData),
    signature: encode(response.signature),
    userHandle: response.userHandle ? encode(response.userHandle) : null,
  };
}

export function enablePasskeyForm(form) {
  const button = form.querySelector("[data-passkey-submit]");
  const status = form.querySelector("[data-passkey-status]");

  if (!window.PublicKeyCredential) {
    status.textContent = "Passkeys are unavailable in this browser.";
    return;
  }

  button.disabled = false;
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (button.disabled) return;

    const fields = new FormData(form);
    const token = fields.get("_csrf_token");
    button.disabled = true;
    status.textContent = "";

    try {
      const options = await post(form.dataset.options, token, {});
      if (options.location) {
        window.location.assign(options.location);
        return;
      }

      const challenge = options.challenge;
      options.challenge = decode(challenge);
      const credential =
        form.dataset.passkey === "register"
          ? await createPasskey(options)
          : await getPasskey(options);

      const result = await post(form.action, token, {
        ...credential,
        challenge,
        name: fields.get("name"),
      });

      window.location.assign(result.location);
    } catch (error) {
      status.textContent =
        error.name === "NotAllowedError" || error.name === "AbortError"
          ? "The passkey prompt was cancelled or timed out. Try again."
          : "Could not use the passkey. Check your device and try again.";
    } finally {
      button.disabled = false;
    }
  });
}
