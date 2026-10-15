// =========================================================================
// Pasos de las herramientas que arman un prompt (Secuencias, Tareas).
// Mismo patrón que el flujo del PUD en index.html:
//   Paso 1 (#btn-paso-1): se ilumina mientras falten datos; al tocarlo lleva
//          al primer campo pendiente.
//   Paso 2 (#btn-paso-2): gris hasta completar el paso 1; genera el prompt y,
//          ya generado, dice "Copiá este prompt en tu IA" y lo copia.
// Estilos: .paso-btn en austin-tokens.css. Uso:
//   PasosPrompt.montar({ campos, listo, faltante, enfocar, generar, copiar });
//   PasosPrompt.generado();   // después de armar el prompt
//   PasosPrompt.cambio();     // si cambió algo que afecta al prompt (ej. el PUD)
// =========================================================================
const PasosPrompt = (() => {
    let cfg = null;
    const estado = { generado: false, desactualizado: false };

    function actualizar() {
        if (!cfg) return;
        const listo = cfg.listo();
        const vigente = estado.generado && !estado.desactualizado;

        const paso1 = document.getElementById('btn-paso-1');
        paso1.dataset.estado = listo ? 'hecho' : 'actual';
        document.getElementById('paso-1-estado').textContent = listo ? 'Listo' : cfg.faltante();

        const paso2 = document.getElementById('btn-paso-2');
        paso2.disabled = !listo;
        paso2.dataset.estado = listo ? 'actual' : 'espera';
        document.getElementById('paso-2-texto').textContent = vigente ? 'Copiá este prompt en tu IA'
            : estado.desactualizado ? 'Cambiaste datos: generar el prompt de nuevo' : 'Generar el prompt';
        document.getElementById('paso-2-flecha').hidden = !vigente;
    }

    function cambio() {
        if (estado.generado) estado.desactualizado = true;
        actualizar();
    }

    function montar(config) {
        cfg = config;
        cfg.campos.forEach(el => {
            el.addEventListener('input', cambio);
            el.addEventListener('change', cambio);
        });
        document.getElementById('btn-paso-1').addEventListener('click', () => cfg.enfocar());
        document.getElementById('btn-paso-2').addEventListener('click', () => {
            if (estado.generado && !estado.desactualizado) cfg.copiar();
            else cfg.generar();
        });
        actualizar();
    }

    function generado() {
        estado.generado = true;
        estado.desactualizado = false;
        actualizar();
    }

    return { montar, generado, cambio, actualizar };
})();
