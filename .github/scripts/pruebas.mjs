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
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const PAGINAS = [
  'index.html', 'coordinadores/index.html', 'al-dia/index.html',
  'secuencias-epc.html', 'generador-tareas.html', 'rubrica.html'
];
const SCRIPTS = ['austin-ui.js', 'austin-pasos.js', 'pud-contexto.js', 'nivel-inicial.js'];

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
                     'preguntas', 'preguntas_publicas', 'historial_tests', 'resultados', 'perfiles']) {
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

console.log(fallas ? `\n${fallas} prueba(s) fallaron.` : '\nTodas las pruebas pasaron.');
process.exit(fallas ? 1 : 0);
