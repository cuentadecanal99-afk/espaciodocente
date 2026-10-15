// =========================================================================
// Avisos y diálogos del sistema Austin (reemplazan alert/confirm/prompt).
// Requiere austin-tokens.css. Uso:
//   AustinUI.avisar('PUD guardado.');
//   AustinUI.avisar('No se pudo guardar el PUD.', { tipo: 'error', detalle: error });
//   if (!await AustinUI.confirmar('¿Cancelar esta reserva?', { aceptar: 'Cancelar reserva', peligro: true })) return;
//   const pass = await AustinUI.pedirTexto({ titulo: 'Nueva contraseña', tipo: 'password', validar: v => ... });
// =========================================================================
const AustinUI = (() => {
    let pila = null;

    // Traduce los errores más comunes de Supabase/red a un texto que el
    // docente pueda entender. El mensaje técnico queda como detalle.
    function errorLegible(error) {
        const msg = String(error?.message || error || '');
        if (/failed to fetch|networkerror|network request/i.test(msg)) return 'Sin conexión con el servidor. Revisá tu internet y probá de nuevo.';
        if (/invalid login credentials/i.test(msg)) return 'El correo o la contraseña no son correctos.';
        if (/email not confirmed/i.test(msg)) return 'Todavía no confirmaste tu correo. Revisá tu bandeja de entrada.';
        if (/user already registered/i.test(msg)) return 'Ya existe una cuenta con ese correo. Iniciá sesión o recuperá tu contraseña.';
        if (/jwt|session|not authenticated/i.test(msg)) return 'Tu sesión venció. Volvé a iniciar sesión.';
        if (/permission denied|row-level security|rls/i.test(msg)) return 'No tenés permiso para hacer esta acción.';
        if (/duplicate key|already exists/i.test(msg)) return 'Ese registro ya existe.';
        if (/rate limit|too many/i.test(msg)) return 'Demasiados intentos seguidos. Esperá unos minutos y probá de nuevo.';
        return '';
    }

    function avisar(mensaje, opciones = {}) {
        const { tipo = 'ok', detalle = null, duracion } = opciones;
        if (!pila) {
            pila = document.createElement('div');
            pila.className = 'austin-avisos';
            pila.setAttribute('aria-live', 'polite');
            document.body.appendChild(pila);
        }
        const aviso = document.createElement('div');
        aviso.className = 'austin-aviso' + (tipo === 'error' ? ' error' : '');
        aviso.setAttribute('role', tipo === 'error' ? 'alert' : 'status');

        const texto = document.createElement('p');
        texto.textContent = mensaje;
        if (detalle) {
            const legible = errorLegible(detalle);
            const extra = document.createElement('small');
            extra.textContent = legible || String(detalle?.message || detalle);
            texto.appendChild(extra);
        }
        const cerrar = document.createElement('button');
        cerrar.type = 'button';
        cerrar.setAttribute('aria-label', 'Cerrar aviso');
        cerrar.textContent = '×';
        cerrar.onclick = () => aviso.remove();

        aviso.append(texto, cerrar);
        pila.appendChild(aviso);
        const ms = duracion ?? (tipo === 'error' ? 9000 : 4500);
        if (ms > 0) setTimeout(() => aviso.remove(), ms);
        return aviso;
    }

    // Diálogo modal nativo (<dialog>) con foco atrapado y Esc para cancelar.
    function abrirDialogo({ titulo, mensaje, campo, aceptar, cancelar, peligro }) {
        return new Promise(resolve => {
            const d = document.createElement('dialog');
            d.className = 'austin-dialogo';
            d.innerHTML = `<form method="dialog">
                <h3></h3><p></p>
                ${campo ? '<label></label><input autocomplete="off"><div class="austin-dialogo-error" aria-live="polite"></div>' : ''}
                <div class="austin-dialogo-acciones">
                    <button type="submit" value="ok"></button>
                    <button type="submit" value="cancelar" formnovalidate></button>
                </div></form>`;
            d.querySelector('h3').textContent = titulo;
            const p = d.querySelector('p');
            if (mensaje) p.textContent = mensaje; else p.remove();
            // "Aceptar" va primero en el HTML para que Enter lo use; el CSS lo muestra a la derecha.
            const [btnOk, btnCancelar] = d.querySelectorAll('.austin-dialogo-acciones button');
            btnCancelar.textContent = cancelar || 'Cancelar';
            btnOk.textContent = aceptar || 'Aceptar';
            if (peligro) btnOk.classList.add('peligro');

            const input = d.querySelector('input');
            if (input) {
                d.querySelector('label').textContent = campo.etiqueta || titulo;
                input.type = campo.tipo || 'text';
                if (campo.tipo === 'password') input.autocomplete = 'new-password';
                input.value = campo.valor || '';
                input.id = 'austin-dialogo-campo';
                d.querySelector('label').htmlFor = input.id;
                btnOk.addEventListener('click', (e) => {
                    const error = campo.validar ? campo.validar(input.value) : '';
                    if (error) {
                        e.preventDefault();
                        d.querySelector('.austin-dialogo-error').textContent = error;
                        input.focus();
                    }
                });
            }

            d.addEventListener('close', () => {
                const ok = d.returnValue === 'ok';
                d.remove();
                resolve(input ? (ok ? input.value : null) : ok);
            });
            document.body.appendChild(d);
            d.showModal();
            // En acciones destructivas, el foco arranca en la opción segura.
            (input || (peligro ? btnCancelar : btnOk)).focus();
        });
    }

    function confirmar(mensaje, opciones = {}) {
        return abrirDialogo({ titulo: opciones.titulo || mensaje, mensaje: opciones.titulo ? mensaje : '', ...opciones });
    }

    function pedirTexto(opciones = {}) {
        return abrirDialogo({
            titulo: opciones.titulo || 'Ingresá un dato',
            mensaje: opciones.mensaje,
            aceptar: opciones.aceptar || 'Guardar',
            campo: { etiqueta: opciones.etiqueta, tipo: opciones.tipo, valor: opciones.valor, validar: opciones.validar }
        });
    }

    return { avisar, confirmar, pedirTexto, errorLegible };
})();
