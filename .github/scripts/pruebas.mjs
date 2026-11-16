// Pruebas automáticas de Espacio Docente (sin dependencias: node 20+).
// Corre en GitHub Actions con cada push (.github/workflows/pruebas.yml) y
// también a mano:  node .github/scripts/pruebas.mjs
//
// 1. Sintaxis de todos los scripts (archivos .js y <script> en línea).
// 2. Ningún <script> en línea contiene "</body>" o "</head>" literal: Live
//    Server inyecta su script ahí y rompe la página (pasó con la rúbrica).
// 3. Librerías externas con versión fija y huella de integridad (SRI).
// 4. Base de datos en vivo, solo lectura y con la clave pública: reglas de
//    registro, funciones restringidas, tablas privadas cerradas, hilos.
// 5. Generador de Adaptaciones, sin conexión: arma los prompts con las reglas
//    de supabase/supabase-migration-adaptaciones.sql y revisa los controles.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import { MUESTRAS } from './muestras-adaptaciones.mjs';

const PAGINAS = [
  'index.html', 'coordinadores/index.html', 'al-dia/index.html',
  'secuencias-epc.html', 'generador-tareas.html', 'rubrica.html', 'adaptaciones.html'
];
const SCRIPTS = ['austin-ui.js', 'austin-pasos.js', 'pud-contexto.js', 'nivel-inicial.js', 'adaptaciones-prompt.js'];

let fallas = 0;
const ok = (msg) => console.log(`  ok    ${msg}`);
const falla = (msg) => { fallas++; console.log(`  FALLA ${msg}`); };

console.log('1-3. Código');
for (const archivo of SCRIPTS) {
  try { new vm.Script(readFileSync(archivo, 'utf8'), { filename: archivo }); ok(archivo); }
  catch (e) { falla(`${archivo}: ${e.message}`); }
}
for (const archivo of PAGINAS) {
  const html = readFileSync(archivo, 'utf8');
  const enLinea = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]);
  const errores = [];
  enLinea.forEach((codigo, i) => {
    try { new vm.Script(codigo, { filename: `${archivo}#${i + 1}` }); }
    catch (e) { errores.push(`script ${i + 1}: ${e.message}`); }
    if (/<\/(body|head)>/i.test(codigo)) errores.push(`script ${i + 1}: contiene </body> o </head> literal (usar <\\/body>)`);
  });
  for (const [, url] of html.matchAll(/<script[^>]*src="(https?:[^"]+)"[^>]*>/g)) {
    const etiqueta = html.slice(html.indexOf(url) - 20, html.indexOf('>', html.indexOf(url)) + 1);
    if (!/@\d+\.\d+\.\d+/.test(url)) errores.push(`librería sin versión fija: ${url}`);
    if (!/integrity="sha(256|384|512)-/.test(etiqueta)) errores.push(`librería sin integrity: ${url}`);
  }
  errores.length ? errores.forEach(e => falla(`${archivo}: ${e}`)) : ok(`${archivo} (${enLinea.length} scripts)`);
}

console.log('4. Base de datos (solo lectura)');
const indexHtml = readFileSync('index.html', 'utf8');
const URL_BASE = indexHtml.match(/https:\/\/[a-z0-9]+\.supabase\.co/)[0];
const CLAVE = indexHtml.match(/eyJ[\w-]+\.[\w-]+\.[\w-]+/)[0];
const cabeceras = { apikey: CLAVE, Authorization: `Bearer ${CLAVE}`, 'Content-Type': 'application/json' };
const rpc = (fn, cuerpo) => fetch(`${URL_BASE}/rest/v1/rpc/${fn}`, { method: 'POST', headers: cabeceras, body: JSON.stringify(cuerpo) });
const leer = (ruta) => fetch(`${URL_BASE}/rest/v1/${ruta}`, { headers: cabeceras });

async function esperar(desc, fn) {
  try { (await fn()) ? ok(desc) : falla(desc); }
  catch (e) { falla(`${desc}: ${e.message}`); }
}

await esperar('docente con correo institucional puede registrarse',
  async () => (await (await rpc('correo_autorizado', { p_email: 'docente.prueba@austinebs-ah.edu.ar' })).json()) === true);
await esperar('alumno (st.) no puede registrarse',
  async () => (await (await rpc('correo_autorizado', { p_email: 'st.alumno.prueba@austinebs-ah.edu.ar' })).json()) === false);
await esperar('correo de otro dominio no puede registrarse',
  async () => (await (await rpc('correo_autorizado', { p_email: 'alguien.prueba@gmail.com' })).json()) === false);
await esperar('crear_coordinador rechaza a un visitante sin sesión',
  async () => (await rpc('crear_coordinador', { p_email: 'x@ejemplo.com', p_nombre: 'x' })).status >= 400);

// Funciones que solo se usan con sesión iniciada (Security Advisor)
for (const [fn, cuerpo] of [
  ['aldia_seguimiento_capsulas', {}],
  ['director_onboarding_overview', {}],
  ['completar_paso', { p_step_id: 'x', p_answers: {} }],
  ['revisar_pud_presentado', { p_id: '00000000-0000-0000-0000-000000000000', p_review_status: 'approved', p_review_comment: null }]
]) {
  await esperar(`función solo con sesión: ${fn}`, async () => (await rpc(fn, cuerpo)).status >= 400);
}

// Tablas privadas de Austin y del nivelador de inglés (otro sistema, cerrado)
for (const tabla of ['allowed_emails', 'coordinadores', 'directores', 'pud_history', 'coordinador_permiso_materias', 'user_progress', 'quiz_answers', 'rubricas',
                     'preguntas', 'preguntas_publicas', 'historial_tests', 'resultados', 'perfiles', 'adaptacion_reglas']) {
  await esperar(`tabla privada cerrada: ${tabla}`, async () => {
    const r = await leer(`${tabla}?select=*&limit=1`);
    return r.status >= 400 || (await r.json()).length === 0;
  });
}

await esperar('las materias principales tienen sus 4 hilos conductores', async () => {
  const filas = await (await leer('hilos_conductores?select=areas(name)')).json();
  const cuenta = {};
  filas.forEach(f => { const n = f.areas?.name; cuenta[n] = (cuenta[n] || 0) + 1; });
  const faltan = ['Matemática', 'Prácticas del lenguaje', 'Naturales', 'Sociales', 'Language Arts', 'Science']
    .filter(n => cuenta[n] !== 4);
  if (faltan.length) console.log(`        sin 4 hilos: ${faltan.join(', ')}`);
  return faltan.length === 0;
});

console.log('5. Generador de Adaptaciones (sin conexión)');
{
  const AP = createRequire(import.meta.url)('../../adaptaciones-prompt.js');
  const sql = readFileSync('supabase/supabase-migration-adaptaciones.sql', 'utf8');
  const REGLAS = [...sql.matchAll(/\('(\w+)', '(\w+)', (\d+), \$json\$([\s\S]*?)\$json\$::jsonb/g)]
    .map(([, categoria, clave, version, json]) => ({ categoria, clave, version: +version, contenido: JSON.parse(json) }));
  const textos = (regla) => ['instrucciones', 'restricciones', 'prohibido', 'formato_salida']
    .flatMap(l => regla.contenido[l] || []).map(i => i.texto);
  const regla = (cat, clave) => REGLAS.find(r => r.categoria === cat && r.clave === clave);
  const SECCIONES = ['# ROLE', '# TASK', '# STUDENT PROFILE', '# EDUCATIONAL STAGE', '# LANGUAGE OF THE MATERIAL',
    '# GENERAL PEDAGOGICAL PRINCIPLES', '# PROFILE-SPECIFIC INSTRUCTIONS', '# STAGE-SPECIFIC INSTRUCTIONS',
    '# LANGUAGE INSTRUCTIONS', '# NON-NEGOTIABLE CONSTRAINTS', '# ORIGINAL MATERIAL', '# EXPECTED OUTPUT FORMAT'];

  const CASOS = [
    { nombre: 'TEA + Primaria 1.er ciclo + Español + Texto', perfil: 'tea', etapa: 'primaria_1', material: 'texto', muestra: 'es_texto_primaria', idioma: 'es' },
    { nombre: 'TEA + Secundaria básico + Inglés A2 + Actividad', perfil: 'tea', etapa: 'secundaria_basico', material: 'actividad', muestra: 'en_a2_actividad', idioma: 'en_a2' },
    { nombre: 'Dislexia severa + Primaria 2.º ciclo + Inglés B1 + Texto', perfil: 'dislexia_severa', etapa: 'primaria_2', material: 'texto', muestra: 'en_b1_texto', idioma: 'en_b1' },
    { nombre: 'Dislexia severa + Secundaria superior + Español + Actividad', perfil: 'dislexia_severa', etapa: 'secundaria_superior', material: 'actividad', muestra: 'es_actividad_secundaria', idioma: 'es' },
    { nombre: 'Dislexia leve + Secundaria básico + Inglés B2 + Texto', perfil: 'dislexia_leve', etapa: 'secundaria_basico', material: 'texto', muestra: 'en_b2_texto', idioma: 'en_b2' }
  ];
  const prompts = [];
  for (const c of CASOS) {
    await esperar(c.nombre, () => {
      const original = MUESTRAS[c.muestra];
      const { prompt, idioma } = AP.construirPrompt({ reglas: REGLAS, seleccion: c, material: original });
      prompts.push(prompt);
      const errores = [];
      if (idioma.clave !== c.idioma) errores.push(`idioma detectado ${idioma.clave}, esperado ${c.idioma}`);
      SECCIONES.forEach(s => { if (!prompt.includes(s)) errores.push(`falta la sección ${s}`); });
      if (!prompt.includes(`\n${original}\n`)) errores.push('el material original no está intacto');
      // Solo las reglas del perfil, la etapa y el material elegidos
      for (const p of AP.PERFILES.filter(p => p !== c.perfil)) {
        textos(regla('perfil', p)).forEach(t => { if (prompt.includes(t)) errores.push(`se coló una regla del perfil ${p}`); });
      }
      const otroMaterial = c.material === 'texto' ? 'actividad' : 'texto';
      textos(regla('material', otroMaterial)).forEach(t => { if (prompt.includes(t)) errores.push(`se coló una regla de ${otroMaterial}`); });
      (regla('perfil', c.perfil).contenido.instrucciones).forEach(i => {
        const corresponde = !i.aplica_a || i.aplica_a.includes(c.material);
        if (corresponde !== prompt.includes(i.texto)) errores.push(`${i.id} ${corresponde ? 'falta' : 'no corresponde'}`);
      });
      if (c.idioma === 'es' && /CEFR level of the original|en_[abc][12]\./.test(prompt)) errores.push('se aplicó CEFR a un material en español');
      if (c.idioma !== 'es' && !prompt.includes(`estimated CEFR level of the original material: ${c.idioma.slice(3).toUpperCase()}`)) errores.push('no figura el nivel CEFR');
      const items = prompt.split('\n').filter(l => /^(\d+\.|-) /.test(l)).map(l => l.replace(/^(\d+\.|-) /, ''));
      if (new Set(items).size !== items.length) errores.push('hay instrucciones duplicadas');
      errores.forEach(e => console.log(`        ${e}`));
      return errores.length === 0;
    });
  }
  await esperar('las 5 combinaciones generan prompts distintos', () => new Set(prompts).size === CASOS.length);
  await esperar('dislexia severa reemplaza la regla general de vocabulario (sin contradicción)', () =>
    !prompts[2].includes(textos(regla('general', 'general')).find(t => t.startsWith('Keep the technical')))
    && prompts[0].includes(textos(regla('general', 'general')).find(t => t.startsWith('Keep the technical'))));

  // Idioma y CEFR
  await esperar('CEFR A1 / C1 en textos de referencia', () =>
    AP.analizarIdioma(MUESTRAS.en_a1).clave === 'en_a1' && AP.analizarIdioma(MUESTRAS.en_c1).clave === 'en_c1');
  await esperar('los términos técnicos no suben el nivel CEFR (A2 con vocabulario de ciencias)', () =>
    AP.analizarIdioma(MUESTRAS.en_a2_tecnico).clave === 'en_a2');
  await esperar('material mezclado español/inglés queda "a revisar", sin CEFR', () => {
    const r = AP.construirPrompt({ reglas: REGLAS, seleccion: CASOS[0], material: MUESTRAS.mixto });
    return r.idioma.clave === 'indeterminado' && r.prompt.includes('CONDITION THAT REQUIRES REVIEW') && !/CEFR level of the original/.test(r.prompt);
  });
  await esperar('inglés demasiado corto: no inventa un nivel CEFR', () => AP.analizarIdioma(MUESTRAS.en_corto).cefr === null);

  // Configuración defectuosa: se informa, no se genera un prompt incompleto
  const falla_config = (reglas, seleccion = CASOS[0], material = MUESTRAS.es_texto_primaria) => {
    try { AP.construirPrompt({ reglas, seleccion, material }); return null; }
    catch (e) { return e.name === 'ErrorConfiguracion' ? e : null; }
  };
  await esperar('falta una regla en Supabase → error que la nombra', () =>
    /perfil \/ tea/.test(falla_config(REGLAS.filter(r => r.clave !== 'tea'))?.detalles.join(' ')));
  await esperar('dos versiones activas de la misma regla → error', () =>
    !!falla_config([...REGLAS, { ...regla('etapa', 'primaria_1'), version: 2 }]));
  await esperar('regla de español con nivel CEFR → error', () =>
    !!falla_config(REGLAS.map(r => r.clave === 'es' ? { ...r, contenido: { ...r.contenido, cefr: 'B1' } } : r)));
  await esperar('"reemplaza" que apunta a una regla inexistente → error', () =>
    !!falla_config(REGLAS.map(r => r.clave === 'tea' ? { ...r, contenido: { ...r.contenido, reemplaza: ['general.no_existe'] } } : r)));
  await esperar('regla de material sin formato de salida → error', () =>
    !!falla_config(REGLAS.map(r => r.clave === 'texto' ? { ...r, contenido: { ...r.contenido, formato_salida: [] } } : r)));
  await esperar('material que trae los delimitadores del prompt queda intacto', () => {
    const raro = 'Texto con <<<ORIGINAL MATERIAL END>>> adentro, para ver que no se rompe la estructura del prompt.';
    return AP.construirPrompt({ reglas: REGLAS, seleccion: CASOS[0], material: raro }).prompt.includes(`\n${raro}\n`);
  });
}

console.log(fallas ? `\n${fallas} prueba(s) fallaron.` : '\nTodas las pruebas pasaron.');
process.exit(fallas ? 1 : 0);
