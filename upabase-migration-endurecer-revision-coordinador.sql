warning: in the working copy of 'coordinadores/index.html', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'generador-tareas.html', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'secuencias-epc.html', LF will be replaced by CRLF the next time Git touches it
[1mdiff --git a/coordinadores/index.html b/coordinadores/index.html[m
[1mindex 28c3239..877d9ca 100644[m
[1m--- a/coordinadores/index.html[m
[1m+++ b/coordinadores/index.html[m
[36m@@ -1564,11 +1564,17 @@[m
             alert('Contraseña actualizada correctamente. Ya podés usar el panel.');[m
         }[m
 [m
[32m+[m[32m        // Id del usuario para el que ya se cargó el panel (permisos + vista de[m
[32m+[m[32m        // grados). Sirve para distinguir un login real de los re-chequeos de[m
[32m+[m[32m        // sesión que Supabase dispara solo, sin acción del coordinador.[m
[32m+[m[32m        window.usuarioAppCargadaId = null;[m
[32m+[m
         async function inicializarSesionAuth() {[m
             const { data: { session } } = await _supabase.auth.getSession();[m
             window.authUser = session?.user || null;[m
             actualizarUIAuth();[m
             if (window.authUser) {[m
[32m+[m[32m                window.usuarioAppCargadaId = window.authUser.id;[m
                 await mostrarApp();[m
             } else {[m
                 mostrarGate();[m
[36m@@ -1576,17 +1582,29 @@[m
         }[m
 [m
         _supabase.auth.onAuthStateChange((event, session) => {[m
[31m-            window.authUser = session?.user || null;[m
[32m+[m[32m            const nuevoUser = session?.user || null;[m
[32m+[m[32m            window.authUser = nuevoUser;[m
             actualizarUIAuth();[m
             if (event === 'PASSWORD_RECOVERY') {[m
                 manejarRecuperacionPassword();[m
                 return;[m
             }[m
[31m-            if (window.authUser) {[m
[31m-                mostrarApp();[m
[31m-            } else if (event === 'SIGNED_OUT') {[m
[32m+[m[32m            if (event === 'SIGNED_OUT') {[m
[32m+[m[32m                window.usuarioAppCargadaId = null;[m
                 mostrarGate();[m
[32m+[m[32m                return;[m
             }[m
[32m+[m[32m            if (!nuevoUser) return;[m
[32m+[m
[32m+[m[32m            // Supabase dispara TOKEN_REFRESHED (y a veces SIGNED_IN de nuevo) cada[m
[32m+[m[32m            // vez que la pestaña recupera el foco, aunque sea el mismo usuario ya[m
[32m+[m[32m            // logueado. Sin este filtro, mostrarApp() volvía a pisar la vista con[m
[32m+[m[32m            // "grados" cada vez que el coordinador volvía de mirar otra ventana,[m
[32m+[m[32m            // cerrando el PUD que tenía abierto.[m
[32m+[m[32m            if (nuevoUser.id === window.usuarioAppCargadaId) return;[m
[32m+[m
[32m+[m[32m            window.usuarioAppCargadaId = nuevoUser.id;[m
[32m+[m[32m            mostrarApp();[m
         });[m
 [m
         inicializarSesionAuth();[m
[1mdiff --git a/generador-tareas.html b/generador-tareas.html[m
[1mindex b7a833c..53b1f58 100644[m
[1m--- a/generador-tareas.html[m
[1m+++ b/generador-tareas.html[m
[36m@@ -365,14 +365,26 @@[m
         '3° Grado Primaria': { label: '3° Grado Primaria', vocabulario: 'Específico del área, siempre explicado en contexto la primera vez que aparece.', gramatica: 'Oraciones de hasta 10 palabras, primeras subordinadas simples.' },[m
         '4° Grado Primaria': { label: '4° Grado Primaria', vocabulario: 'Específico del área con mayor variedad; se pueden introducir sinónimos y familias de palabras.', gramatica: 'Oraciones de hasta 12 palabras, subordinadas simples y conectores de secuencia (primero, luego, finalmente).' },[m
         '5° Grado Primaria': { label: '5° Grado Primaria', vocabulario: 'Técnico del área, con primeras nociones de argumentación y comparación.', gramatica: 'Oraciones de hasta 15 palabras, conectores de causa-consecuencia, subordinadas variadas.' },[m
[31m-        '6° Grado Primaria': { label: '6° Grado Primaria', vocabulario: 'Técnico del área y vocabulario académico de transición a secundaria, con nociones de argumentación.', gramatica: 'Oraciones más complejas, conectores de causa-consecuencia y contraste, primeras estructuras de análisis crítico.' }[m
[32m+[m[32m        '6° Grado Primaria': { label: '6° Grado Primaria', vocabulario: 'Técnico del área y vocabulario académico de transición a secundaria, con nociones de argumentación.', gramatica: 'Oraciones más complejas, conectores de causa-consecuencia y contraste, primeras estructuras de análisis crítico.' },[m
[32m+[m[32m        '1° Año Secundaria': { label: '1° Año Secundaria', vocabulario: 'Técnico del área, introducido en contexto pero ya sin simplificaciones excesivas; primeras nociones de terminología disciplinar.', gramatica: 'Oraciones de hasta 18 palabras, subordinadas variadas, conectores de causa-consecuencia y contraste.' },[m
[32m+[m[32m        '2° Año Secundaria': { label: '2° Año Secundaria', vocabulario: 'Técnico consolidado del área, con primeros términos abstractos propios de la disciplina.', gramatica: 'Subordinadas múltiples, voz pasiva, conectores de consecuencia y concesión; inicio de argumentación con evidencia.' },[m
[32m+[m[32m        '3° Año Secundaria': { label: '3° Año Secundaria', vocabulario: 'Académico y técnico específico, con matices de significado entre términos relacionados.', gramatica: 'Estructuras complejas con varias cláusulas, nexos de contraste y condición; argumentación con postura propia.' },[m
[32m+[m[32m        '4° Año Secundaria': { label: '4° Año Secundaria', vocabulario: 'Especializado del área, incluyendo terminología de uso profesional o académico.', gramatica: 'Registro formal sostenido, estructuras condicionales y comparativas complejas, síntesis de múltiples fuentes.' },[m
[32m+[m[32m        '5° Año Secundaria': { label: '5° Año Secundaria', vocabulario: 'Técnico-académico de nivel preuniversitario, con precisión terminológica exigida.', gramatica: 'Argumentación compleja y sostenida, con matización, contraargumentación y uso de evidencia para sustentar posturas.' },[m
[32m+[m[32m        '6° Año Secundaria': { label: '6° Año Secundaria', vocabulario: 'Académico de transición a nivel universitario, con manejo autónomo de terminología especializada.', gramatica: 'Pensamiento crítico expresado con estructuras sofisticadas, argumentación multicausal y análisis con autonomía total.' }[m
     };[m
 [m
     // Reduce el nivel fino elegido a una de las 3 bandas que ya usan las[m
     // secciones del prompt (requisitos de extensión/complejidad por sección).[m
     const TIER_POR_NIVEL = {[m
         en: { A1: 'inicial', A2: 'inicial', B1: 'medio', B2: 'medio', C1: 'avanzado', C2: 'avanzado' },[m
[31m-        es: { '1° Grado Primaria': 'inicial', '2° Grado Primaria': 'inicial', '3° Grado Primaria': 'medio', '4° Grado Primaria': 'medio', '5° Grado Primaria': 'avanzado', '6° Grado Primaria': 'avanzado' }[m
[32m+[m[32m        es: {[m
[32m+[m[32m            '1° Grado Primaria': 'inicial', '2° Grado Primaria': 'inicial', '3° Grado Primaria': 'medio', '4° Grado Primaria': 'medio', '5° Grado Primaria': 'avanzado', '6° Grado Primaria': 'avanzado',[m
[32m+[m[32m            // Secundaria ya arranca por encima del techo de "avanzado" de primaria;[m
[32m+[m[32m            // no hay un 4° tier de sección, así que los 6 años usan el mismo techo.[m
[32m+[m[32m            '1° Año Secundaria': 'avanzado', '2° Año Secundaria': 'avanzado', '3° Año Secundaria': 'avanzado',[m
[32m+[m[32m            '4° Año Secundaria': 'avanzado', '5° Año Secundaria': 'avanzado', '6° Año Secundaria': 'avanzado'[m
[32m+[m[32m        }[m
     };[m
 [m
     function tablaNiveles(idioma) {[m
[1mdiff --git a/index.html b/index.html[m
[1mindex a66557d..b49f35b 100644[m
[1m--- a/index.html[m
[1m+++ b/index.html[m
[36m@@ -1803,7 +1803,7 @@[m
         }[m
 [m
         const renderAustinPUD = (data) => {[m
[31m-            const hilosHtml = data.throughlines.map(h => `${h}<br>`).join('');[m
[32m+[m[32m            const hilosHtml = data.throughlines.map((h, i) => `<strong>${i + 1}.</strong> ${h}<br>`).join('');[m
             const metasHtml = data.understanding_goals.map(ug => `[m
                 <tr>[m
                     <td style="border: 1pt solid #000; padding: 10px; width: 55%;"><strong>${ug.id}:</strong> ${ug.text}</td>[m
[36m@@ -1911,7 +1911,13 @@[m
             '3° Grado Primaria': { label: '3° Grado Primaria', vocabulario: 'Específico del área, siempre explicado en contexto la primera vez que aparece.', gramatica: 'Oraciones de hasta 10 palabras, primeras subordinadas simples.' },[m
             '4° Grado Primaria': { label: '4° Grado Primaria', vocabulario: 'Específico del área con mayor variedad; se pueden introducir sinónimos y familias de palabras.', gramatica: 'Oraciones de hasta 12 palabras, subordinadas simples y conectores de secuencia (primero, luego, finalmente).' },[m
             '5° Grado Primaria': { label: '5° Grado Primaria', vocabulario: 'Técnico del área, con primeras nociones de argumentación y comparación.', gramatica: 'Oraciones de hasta 15 palabras, conectores de causa-consecuencia, subordinadas variadas.' },[m
[31m-            '6° Grado Primaria': { label: '6° Grado Primaria', vocabulario: 'Técnico del área y vocabulario académico de transición a secundaria, con nociones de argumentación.', gramatica: 'Oraciones más complejas, conectores de causa-consecuencia y contraste, primeras estructuras de análisis crítico.' }[m
[32m+[m[32m            '6° Grado Primaria': { label: '6° Grado Primaria', vocabulario: 'Técnico del área y vocabulario académico de transición a secundaria, con nociones de argumentación.', gramatica: 'Oraciones más complejas, conectores de causa-consecuencia y contraste, primeras estructuras de análisis crítico.' },[m
[32m+[m[32m            '1° Año Secundaria': { label: '1° Año Secundaria', vocabulario: 'Técnico del área, introducido en contexto pero ya sin simplificaciones excesivas; primeras nociones de terminología disciplinar.', gramatica: 'Oraciones de hasta 18 palabras, subordinadas variadas, conectores de causa-consecuencia y contraste.' },[m
[32m+[m[32m            '2° Año Secundaria': { label: '2° Año Secundaria', vocabulario: 'Técnico consolidado del área, con primeros términos abstractos propios de la disciplina.', gramatica: 'Subordinadas múltiples, voz pasiva, conectores de consecuencia y concesión; inicio de argumentación con evidencia.' },[m
[32m+[m[32m            '3° Año Secundaria': { label: '3° Año Secundaria', vocabulario: 'Académico y técnico específico, con matices de significado entre términos relacionados.', gramatica: 'Estructuras complejas con varias cláusulas, nexos de contraste y condición; argumentación con postura propia.' },[m
[32m+[m[32m            '4° Año Secundaria': { label: '4° Año Secundaria', vocabulario: 'Especializado del área, incluyendo terminología de uso profesional o académico.', gramatica: 'Registro formal sostenido, estructuras condicionales y comparativas complejas, síntesis de múltiples fuentes.' },[m
[32m+[m[32m            '5° Año Secundaria': { label: '5° Año Secundaria', vocabulario: 'Técnico-académico de nivel preuniversitario, con precisión terminológica exigida.', gramatica: 'Argumentación compleja y sostenida, con matización, contraargumentación y uso de evidencia para sustentar posturas.' },[m
[32m+[m[32m            '6° Año Secundaria': { label: '6° Año Secundaria', vocabulario: 'Académico de transición a nivel universitario, con manejo autónomo de terminología especializada.', gramatica: 'Pensamiento crítico expresado con estructuras sofisticadas, argumentación multicausal y análisis con autonomía total.' }[m
         };[m
 [m
         function bloqueCalibracionNivel(idioma, datosUsuario) {[m
[36m@@ -2013,7 +2019,7 @@[m [mDATOS DE ENTRADA:[m
 ESTRUCTURA JSON REQUERIDA DE SALIDA:[m
 {[m
   "meta": { "year": "${datosUsuario.year}", "section": "", "subject": "${datosUsuario.subject}" },[m
[31m-  "topic": "Título optimizado",[m
[32m+[m[32m  "topic": "Tópico generativo corto y llamativo (máx. 6 palabras)",[m
   "throughlines": [ "Pregunta 1?", "Pregunta 2?", "Pregunta 3?", "Pregunta 4?" ],[m
   "understanding_goals": [[m
     { "id": "UG 1", "text": "${ejemploMeta}", "dimension": "KNOWLEDGE", "question": "Pregunta guía" },[m
[36m@@ -2022,11 +2028,31 @@[m [mESTRUCTURA JSON REQUERIDA DE SALIDA:[m
     { "id": "UG 4", "text": "${ejemploMeta}", "dimension": "COMMUNICATION", "question": "Pregunta guía" }[m
   ],[m
   "performances": [[m
[31m-    { "title": "Actividad 1", "description": "Detalle", "assessment": "Evaluación", "ug": "1", "upt": "GI", "mi": "L", "td": "3" }[m
[32m+[m[32m    { "title": "Actividad 1", "description": "Detalle", "assessment": "Formal / Escrita / Docente", "ug": "1", "upt": "GI", "mi": "L", "td": "3" }[m
   ],[m
   "final_project": { "title": "Proyecto Final", "description": "Detalle", "mi": "L", "td": "7" }[m
 }[m
[31m-Genera exactamente 4 'throughlines' relevantes y siempre completa 4 aunque el input sea limitado. Genera exactamente 4 'understanding_goals' (repartiendo dimensiones) y al menos 4 'performances' articuladas.`;[m
[32m+[m[32mGenera exactamente 4 'throughlines' relevantes y siempre completa 4 aunque el input sea limitado. Genera exactamente 4 'understanding_goals' (repartiendo dimensiones) y al menos 4 'performances' articuladas.[m
[32m+[m[32mEl 'topic' (tópico generativo) debe ser un título breve y llamativo, tipo titular: máximo 6 palabras, sin puntos ni subordinadas. Nada de oraciones descriptivas extensas ni explicativas.[m
[32m+[m[32mEl campo 'assessment' de cada performance NO debe redactarse como explicación. Debe responder únicamente combinando estas categorías fijas, separadas por " / ", eligiendo una opción de cada grupo:[m
[32m+[m[32m- Formal / Informal[m
[32m+[m[32m- Oral / Escrita / Gestual[m
[32m+[m[32m- Docente / Co-valoración / Autovaloración[m
[32m+[m[32mEjemplo válido: "Formal / Escrita / Docente". No agregues texto adicional, justificación ni descripción del instrumento.[m
[32m+[m
[32m+[m[32mCRITERIOS PARA EL 'final_project' (Proyecto Final):[m
[32m+[m[32mEl objetivo es la CALIDAD del proyecto, no una reformulación decorativa. Mantené el tema central, los objetivos de aprendizaje, las habilidades a desarrollar y la relación con la unidad trabajada. Aplicá estos lineamientos al redactar 'title' y 'description':[m
[32m+[m[32m1. Propósito auténtico: el estudiante debe hacer algo con una razón real, no solo demostrar que leyó o responder preguntas.[m
[32m+[m[32m2. Pensamiento visible: el resultado debe mostrar cómo el estudiante interpreta, compara, decide, resuelve, justifica o conecta ideas. Si una rutina de Visible Thinking (Project Zero) aporta valor real, incorporala de forma natural, sin nombrarla explícitamente como "rutina".[m
[32m+[m[32m3. Inquiry: partí de una pregunta, problema, desafío o decisión que invite a pensar, en vez de reproducir información.[m
[32m+[m[32m4. Producto final claro: un solo resultado concreto y realizable, no múltiples entregables ni un proyecto excesivamente abierto.[m
[32m+[m[32m5. Coherencia: relacionado directamente con lo enseñado en la unidad, sin agregar habilidades sin conexión clara.[m
[32m+[m[32m6. Edad y nivel: realista para la edad y el nivel lingüístico del grupo. La complejidad debe estar en el pensamiento, no en la cantidad de pasos, materiales o lenguaje académico.[m
[32m+[m[32m7. Low-prep: realizable con recursos habituales del aula (el texto trabajado, cuaderno, pizarrón, materiales simples), sin preparación docente extensa.[m
[32m+[m[32m8. Simplicidad: sin etapas, fases ni componentes innecesarios.[m
[32m+[m[32m9. Lenguaje natural, claro y profesional, sin vocabulario pedagógico técnico ni tono de documento universitario o de Instructional Design.[m
[32m+[m[32mEVITÁ que el proyecto se convierta automáticamente en portfolio, exposición, campaña, dossier, producto multimodal, presentación, producto digital o con múltiples entregables: elegí el formato que mejor responda a los objetivos de ESTE proyecto puntual.[m
[32m+[m[32mEl 'description' debe ser un párrafo breve que indique qué harán los estudiantes, cuál es el resultado final concreto, y cómo se hace visible su pensamiento en el proceso. No es necesaria una sección aparte para esto: integralo en el mismo párrafo.`;[m
         }[m
 [m
         function generarPromptEstructurado() {[m
[36m@@ -2133,10 +2159,24 @@[m [mGenera exactamente 4 'throughlines' relevantes y siempre completa 4 aunque el in[m
             }[m
         };[m
 [m
[32m+[m[32m        // El preview es editable (correcciones manuales sobre el PUD ya[m
[32m+[m[32m        // renderizado): pegar ahí debe insertar texto plano en el cursor, no[m
[32m+[m[32m        // intentar reinterpretar todo el contenido como un JSON nuevo. El[m
[32m+[m[32m        // pegado de JSON para generar el PUD tiene su propio cuadro dedicado[m
[32m+[m[32m        // (#json-paster) más abajo.[m
         preview.addEventListener('paste', (e) => {[m
             e.preventDefault();[m
             const text = e.clipboardData.getData('text/plain');[m
[31m-            procesarTextoYRenderizar(text);[m
[32m+[m[32m            const selection = window.getSelection();[m
[32m+[m[32m            if (!selection.rangeCount) return;[m
[32m+[m[32m            const range = selection.getRangeAt(0);[m
[32m+[m[32m            range.deleteContents();[m
[32m+[m[32m            const nodo = document.createTextNode(text);[m
[32m+[m[32m            range.insertNode(nodo);[m
[32m+[m[32m            range.setStartAfter(nodo);[m
[32m+[m[32m            range.collapse(true);[m
[32m+[m[32m            selection.removeAllRanges();[m
[32m+[m[32m            selection.addRange(range);[m
         });[m
 [m
         pasteZone.addEventListener('input', (e) => {[m
[1mdiff --git a/secuencias-epc.html b/secuencias-epc.html[m
[1mindex ce514f4..7402851 100644[m
[1m--- a/secuencias-epc.html[m
[1m+++ b/secuencias-epc.html[m
[36m@@ -312,7 +312,13 @@[m
         '3° Grado Primaria': { label: '3° Grado Primaria', vocabulario: 'Específico del área, siempre explicado en contexto la primera vez que aparece.', gramatica: 'Oraciones de hasta 10 palabras, primeras subordinadas simples.' },[m
         '4° Grado Primaria': { label: '4° Grado Primaria', vocabulario: 'Específico del área con mayor variedad; se pueden introducir sinónimos y familias de palabras.', gramatica: 'Oraciones de hasta 12 palabras, subordinadas simples y conectores de secuencia (primero, luego, finalmente).' },[m
         '5° Grado Primaria': { label: '5° Grado Primaria', vocabulario: 'Técnico del área, con primeras nociones de argumentación y comparación.', gramatica: 'Oraciones de hasta 15 palabras, conectores de causa-consecuencia, subordinadas variadas.' },[m
[31m-        '6° Grado Primaria': { label: '6° Grado Primaria', vocabulario: 'Técnico del área y vocabulario académico de transición a secundaria, con nociones de argumentación.', gramatica: 'Oraciones más complejas, conectores de causa-consecuencia y contraste, primeras estructuras de análisis crítico.' }[m
[32m+[m[32m        '6° Grado Primaria': { label: '6° Grado Primaria', vocabulario: 'Técnico del área y vocabulario académico de transición a secundaria, con nociones de argumentación.', gramatica: 'Oraciones más complejas, conectores de causa-consecuencia y contraste, primeras estructuras de análisis crítico.' },[m
[32m+[m[32m        '1° Año Secundaria': { label: '1° Año Secundaria', vocabulario: 'Técnico del área, introducido en contexto pero ya sin simplificaciones excesivas; primeras nociones de terminología disciplinar.', gramatica: 'Oraciones de hasta 18 palabras, subordinadas variadas, conectores de causa-consecuencia y contraste.' },[m
[32m+[m[32m        '2° Año Secundaria': { label: '2° Año Secundaria', vocabulario: 'Técnico consolidado del área, con primeros términos abstractos propios de la disciplina.', gramatica: 'Subordinadas múltiples, voz pasiva, conectores de consecuencia y concesión; inicio de argumentación con evidencia.' },[m
[32m+[m[32m        '3° Año Secundaria': { label: '3° Año Secundaria', vocabulario: 'Académico y técnico específico, con matices de significado entre términos relacionados.', gramatica: 'Estructuras complejas con varias cláusulas, nexos de contraste y condición; argumentación con postura propia.' },[m
[32m+[m[32m        '4° Año Secundaria': { label: '4° Año Secundaria', vocabulario: 'Especializado del área, incluyendo terminología de uso profesional o académico.', gramatica: 'Registro formal sostenido, estructuras condicionales y comparativas complejas, síntesis de múltiples fuentes.' },[m
[32m+[m[32m        '5° Año Secundaria': { label: '5° Año Secundaria', vocabulario: 'Técnico-académico de nivel preuniversitario, con precisión terminológica exigida.', gramatica: 'Argumentación compleja y sostenida, con matización, contraargumentación y uso de evidencia para sustentar posturas.' },[m
[32m+[m[32m        '6° Año Secundaria': { label: '6° Año Secundaria', vocabulario: 'Académico de transición a nivel universitario, con manejo autónomo de terminología especializada.', gramatica: 'Pensamiento crítico expresado con estructuras sofisticadas, argumentación multicausal y análisis con autonomía total.' }[m
     };[m
 [m
     function tablaNiveles(idioma) {[m
