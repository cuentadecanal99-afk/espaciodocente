-- =========================================================
-- Migración: Generador de Adaptaciones (reglas pedagógicas en JSON)
-- Correr a mano en Supabase SQL Editor. Idempotente.
--
-- Contexto: la pestaña "Adaptaciones" de Espacio Docente arma un prompt
-- (en inglés) para pegar en una IA externa. NO llama a ninguna IA. Todas
-- las reglas pedagógicas viven en esta tabla, una fila por regla, y el
-- constructor (adaptaciones-prompt.js) recupera y combina en el momento
-- solo las que corresponden a lo que eligió el docente:
--
--   categoria  clave
--   general    general
--   perfil     tea | dislexia_severa | dislexia_leve
--   etapa      inicial | primaria_1 | primaria_2 | secundaria_basico | secundaria_superior
--   material   texto | actividad
--   idioma     es | en_a1 .. en_c2 | en_sin_nivel | indeterminado
--
-- No hay combinaciones predefinidas: cada pedido trae exactamente 5 filas
-- (una por categoría). Cómo editar, versionar y activar reglas:
-- supabase/ADAPTACIONES.md.
--
-- Las tablas viejas perfiles_dislexia y niveles_idioma (prototipo
-- indexADAPT.html, vacías) no se tocan.
-- =========================================================

-- ---------- Validación del JSON (se usa en un CHECK) ----------
-- Así una regla mal cargada desde el Table Editor se rechaza al guardar,
-- en lugar de romper el prompt de los docentes.
CREATE OR REPLACE FUNCTION public.adaptacion_contenido_valido(p_categoria text, p_clave text, c jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  lista text;
  item jsonb;
  ref jsonb;
BEGIN
  IF c IS NULL OR jsonb_typeof(c) <> 'object' THEN RETURN false; END IF;
  IF coalesce(c->>'etiqueta', '') = '' THEN RETURN false; END IF;
  IF jsonb_typeof(c->'instrucciones') IS DISTINCT FROM 'array' OR jsonb_array_length(c->'instrucciones') = 0 THEN RETURN false; END IF;

  -- Campos obligatorios según la categoría
  IF p_categoria = 'general' AND (coalesce(c->>'rol', '') = '' OR coalesce(c->>'precedencia', '') = ''
     OR jsonb_typeof(c->'restricciones') IS DISTINCT FROM 'array' OR jsonb_array_length(c->'restricciones') = 0) THEN
    RETURN false;
  END IF;
  IF p_categoria IN ('perfil', 'etapa') AND coalesce(c->>'descripcion', '') = '' THEN RETURN false; END IF;
  IF p_categoria = 'material' AND (coalesce(c->>'tarea', '') = ''
     OR jsonb_typeof(c->'formato_salida') IS DISTINCT FROM 'array' OR jsonb_array_length(c->'formato_salida') = 0
     OR jsonb_typeof(c->'prohibido') IS DISTINCT FROM 'array' OR jsonb_array_length(c->'prohibido') = 0) THEN
    RETURN false;
  END IF;
  IF p_categoria = 'idioma' THEN
    IF coalesce(c->>'idioma_salida', '') = '' OR jsonb_typeof(c->'requiere_revision') IS DISTINCT FROM 'boolean' THEN RETURN false; END IF;
    -- CEFR solo en las reglas en_a1..en_c2, y tiene que coincidir con la clave
    IF p_clave ~ '^en_(a1|a2|b1|b2|c1|c2)$' THEN
      IF c->>'cefr' IS DISTINCT FROM upper(substr(p_clave, 4)) THEN RETURN false; END IF;
    ELSIF c ? 'cefr' AND jsonb_typeof(c->'cefr') <> 'null' THEN
      RETURN false;
    END IF;
    IF (c->>'requiere_revision')::boolean AND coalesce(c->>'nota_revision', '') = '' THEN RETURN false; END IF;
  END IF;

  -- Cada instrucción: { "id": "<clave>.<algo>", "texto": "...", "aplica_a"?: ["texto"|"actividad"] }
  FOREACH lista IN ARRAY ARRAY['instrucciones', 'restricciones', 'prohibido', 'formato_salida'] LOOP
    IF c ? lista THEN
      IF jsonb_typeof(c->lista) <> 'array' THEN RETURN false; END IF;
      FOR item IN SELECT * FROM jsonb_array_elements(c->lista) LOOP
        IF jsonb_typeof(item) <> 'object' OR coalesce(btrim(item->>'texto'), '') = '' THEN RETURN false; END IF;
        IF coalesce(item->>'id', '') !~ ('^' || p_clave || '\.[a-z0-9_]+$') THEN RETURN false; END IF;
        IF item ? 'aplica_a' THEN
          -- Solo perfil y etapa distinguen texto/actividad dentro de una misma regla
          IF p_categoria NOT IN ('perfil', 'etapa') OR lista <> 'instrucciones' THEN RETURN false; END IF;
          IF jsonb_typeof(item->'aplica_a') <> 'array' OR jsonb_array_length(item->'aplica_a') = 0
             OR NOT (item->'aplica_a' <@ '["texto","actividad"]'::jsonb) THEN
            RETURN false;
          END IF;
        END IF;
      END LOOP;
    END IF;
  END LOOP;

  -- "reemplaza": ids de instrucciones generales que esta regla sustituye
  IF c ? 'reemplaza' THEN
    IF p_categoria = 'general' OR jsonb_typeof(c->'reemplaza') <> 'array' THEN RETURN false; END IF;
    FOR ref IN SELECT * FROM jsonb_array_elements(c->'reemplaza') LOOP
      IF jsonb_typeof(ref) <> 'string' OR (ref #>> '{}') !~ '^general\.[a-z0-9_]+$' THEN RETURN false; END IF;
    END LOOP;
  END IF;

  RETURN true;
END;
$$;

-- ---------- Tabla ----------
CREATE TABLE IF NOT EXISTS public.adaptacion_reglas (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  categoria text NOT NULL CHECK (categoria IN ('general', 'perfil', 'etapa', 'material', 'idioma')),
  clave text NOT NULL CHECK (clave ~ '^[a-z0-9_]+$'),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  activa boolean NOT NULL DEFAULT true,
  contenido jsonb NOT NULL,
  notas text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (categoria, clave, version),
  CONSTRAINT adaptacion_reglas_contenido_valido CHECK (public.adaptacion_contenido_valido(categoria, clave, contenido)),
  CONSTRAINT adaptacion_reglas_general_unica CHECK (categoria <> 'general' OR clave = 'general')
);

-- Una sola versión activa por regla
CREATE UNIQUE INDEX IF NOT EXISTS adaptacion_reglas_una_activa
  ON public.adaptacion_reglas (categoria, clave) WHERE activa;

CREATE OR REPLACE FUNCTION public.adaptacion_reglas_touch()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS adaptacion_reglas_touch ON public.adaptacion_reglas;
CREATE TRIGGER adaptacion_reglas_touch BEFORE UPDATE ON public.adaptacion_reglas
  FOR EACH ROW EXECUTE FUNCTION public.adaptacion_reglas_touch();

-- ---------- Permisos ----------
-- Lectura: solo docentes con sesión y solo reglas activas. La edición se
-- hace desde el dashboard de Supabase (rol de servicio, no pasa por RLS).
ALTER TABLE public.adaptacion_reglas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.adaptacion_reglas FROM anon, authenticated;
GRANT SELECT ON public.adaptacion_reglas TO authenticated;
DROP POLICY IF EXISTS adaptacion_reglas_select_activas ON public.adaptacion_reglas;
CREATE POLICY adaptacion_reglas_select_activas ON public.adaptacion_reglas
  FOR SELECT TO authenticated USING (activa);
REVOKE ALL ON FUNCTION public.adaptacion_contenido_valido(text, text, jsonb) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.adaptacion_reglas_touch() FROM public, anon, authenticated;

-- =========================================================
-- Reglas iniciales (versión 1). El texto de las instrucciones está en
-- inglés porque el prompt se redacta en inglés. ON CONFLICT: correr la
-- migración otra vez no pisa reglas ya editadas.
-- =========================================================
INSERT INTO public.adaptacion_reglas (categoria, clave, version, contenido, notas) VALUES

-- ---------------------------------------------------------
-- GENERAL
-- ---------------------------------------------------------
('general', 'general', 1, $json${
  "etiqueta": "General principles",
  "rol": "You are an expert in inclusive education and Universal Design for Learning, specialised in adapting school materials for students with specific learning profiles. You support the student's teacher: your adaptation removes access barriers while keeping the learning that the teacher designed.",
  "precedencia": "The specific instructions (student profile, educational stage, type of material and language) refine the general principles for this case. If a specific instruction is more precise than a general one, follow the specific one. No instruction can override the non-negotiable constraints.",
  "instrucciones": [
    {"id": "general.objetivos", "texto": "Preserve the original learning objectives: the adapted version must allow the student to learn or demonstrate exactly what the original intends."},
    {"id": "general.conceptos", "texto": "Keep all the essential concepts and the disciplinary content. Reduce access barriers, not content."},
    {"id": "general.vocabulario_tecnico", "texto": "Keep the technical and subject-specific vocabulary that the student needs to learn. Support it (for example, with a brief explanation the first time it appears) instead of replacing it with everyday words."},
    {"id": "general.barreras", "texto": "Adapt only the access barriers that correspond to the student profile described above. Do not apply adaptations designed for other profiles."},
    {"id": "general.diferenciar", "texto": "Distinguish three different kinds of difficulty and address each one separately: (1) decoding and reading fluency, (2) conceptual understanding, (3) written production. A difficulty in one of them does not imply a difficulty in the others."},
    {"id": "general.no_intelectual", "texto": "Do not treat reading or writing difficulties as intellectual difficulties. Assume that the student's reasoning capacity is in line with the stage."},
    {"id": "general.no_infantilizar", "texto": "Do not infantilise the material: keep a tone, register, examples and presentation appropriate to the student's age and educational stage."},
    {"id": "general.nivel_cognitivo", "texto": "Do not automatically lower the cognitive demand. Simplify how the student accesses the information, not how deeply the student is asked to think."},
    {"id": "general.pensamiento_superior", "texto": "Do not remove passages or tasks that require inference, comparison, interpretation, justification or critical thinking. If one of them is hard to access, scaffold it instead of removing it."},
    {"id": "general.no_inventar", "texto": "Do not invent information, data, examples or facts, and do not add content that is not in the original material."}
  ],
  "restricciones": [
    {"id": "general.r_idioma", "texto": "Keep the language of the original material. Do not translate any part of it."},
    {"id": "general.r_hechos", "texto": "Do not change facts, data, figures, dates, names, formulas, quotations or the meaning of the original."},
    {"id": "general.r_no_omitir", "texto": "Do not omit content that the original teaches or assesses. Reorganising, segmenting or rewording is allowed; deleting essential content is not."},
    {"id": "general.r_alcance", "texto": "Adapt only the material provided. Do not add resources, sections or materials that were not requested."}
  ]
}$json$::jsonb, 'Principios que se aplican a todas las adaptaciones.'),

-- ---------------------------------------------------------
-- PERFILES
-- ---------------------------------------------------------
('perfil', 'tea', 1, $json${
  "etiqueta": "Autism spectrum (ASD)",
  "descripcion": "The student is on the autism spectrum. Typical access barriers are figurative or implicit language, ambiguous or open-ended instructions, unpredictable structure, high visual load and implicit social or emotional inferences. Knowledge and reasoning are not assumed to be reduced.",
  "instrucciones": [
    {"id": "tea.literal", "texto": "Replace figurative language, idioms, irony, sarcasm and rhetorical questions with literal wording. If a figure of speech is itself the content being studied (for example, a lesson about metaphors), keep it and add a literal explanation next to it."},
    {"id": "tea.explicito", "texto": "Make implicit information explicit: who does what, when, why and what happens next. Do not rely on reading between the lines for information that is not the learning target."},
    {"id": "tea.estructura", "texto": "Use a predictable, consistent structure: clear headings, the same order and format for equivalent parts, and one idea per paragraph."},
    {"id": "tea.terminos", "texto": "Use the same term for the same concept throughout. Do not alternate synonyms for variety."},
    {"id": "tea.carga_visual", "texto": "Reduce visual clutter: no decorative elements or emojis, and use bold sparingly, only for key terms."},
    {"id": "tea.inferencias_sociales", "texto": "When the material requires understanding intentions, emotions or social situations, keep that demand but support it with explicit cues (what is said or done that shows it)."},
    {"id": "tea.anticipar_texto", "texto": "Begin the text with one or two sentences that state what it is about and how it is organised.", "aplica_a": ["texto"]},
    {"id": "tea.anticipar_actividad", "texto": "Begin with a short numbered list of the parts of the activity, so the student can anticipate the whole sequence.", "aplica_a": ["actividad"]},
    {"id": "tea.consignas_precisas", "texto": "Write each instruction as a precise statement: what to do, how much (for example, 'write 3 reasons'), in what format, and how the student knows the task is finished. Avoid vague expressions such as 'say something about' or 'explain freely'.", "aplica_a": ["actividad"]},
    {"id": "tea.preguntas_abiertas", "texto": "Keep open and inferential questions, but add a concrete frame (which aspect to focus on, a sentence starter or the expected type of answer) so that the expectation is unambiguous.", "aplica_a": ["actividad"]}
  ]
}$json$::jsonb, 'Trastorno del espectro autista.'),

('perfil', 'dislexia_severa', 1, $json${
  "etiqueta": "Severe dyslexia",
  "descripcion": "The student has a severe specific difficulty with decoding, reading fluency and spelling. Reading requires great effort and time, and reading comprehension can be affected by the decoding load, while oral comprehension and reasoning are in line with the stage. Written production (spelling, length, organisation on the page) is a major barrier.",
  "reemplaza": ["general.vocabulario_tecnico"],
  "instrucciones": [
    {"id": "dislexia_severa.vocabulario", "texto": "Keep the technical terms the student must learn, introduce each one with a short, clear explanation the first time it appears, and repeat it consistently. For non-technical vocabulary, prefer high-frequency words."},
    {"id": "dislexia_severa.frases", "texto": "Use short sentences, ideally one idea per sentence, in the most common word order of the language. Avoid long chains of subordinate clauses, double negatives and unnecessary passive voice."},
    {"id": "dislexia_severa.parrafos", "texto": "Use short paragraphs (three or four sentences) separated by a blank line."},
    {"id": "dislexia_severa.formato", "texto": "Use a dyslexia-friendly layout: left-aligned text, bold (never italics or underlining) for emphasis, and lists instead of dense paragraphs when the content enumerates items."},
    {"id": "dislexia_severa.carga_texto", "texto": "Reduce the total reading load by removing redundancy and secondary detail that the learning objectives do not need, without removing essential content.", "aplica_a": ["texto"]},
    {"id": "dislexia_severa.anticipar", "texto": "Begin the text with two or three short sentences that anticipate its main idea, so the student reads with a clear purpose.", "aplica_a": ["texto"]},
    {"id": "dislexia_severa.consignas", "texto": "Write each instruction separately and numbered, with one action per instruction, and put the action verb in bold.", "aplica_a": ["actividad"]},
    {"id": "dislexia_severa.lectura_consigna", "texto": "Reduce the reading load of the activity itself: short instructions and short question stems. If the activity requires reading a source, keep the source reference and indicate clearly which part to read.", "aplica_a": ["actividad"]},
    {"id": "dislexia_severa.produccion", "texto": "Minimise the amount of writing required without lowering the thinking required: allow short answers, keywords, sentence frames to complete, choosing and justifying, matching, diagrams or oral answers. If the original requires an extended written text, keep the task but provide a structure (sentence starters, a paragraph outline).", "aplica_a": ["actividad"]}
  ]
}$json$::jsonb, 'Dislexia severa.'),

('perfil', 'dislexia_leve', 1, $json${
  "etiqueta": "Mild dyslexia",
  "descripcion": "The student has a mild specific difficulty with decoding and reading fluency: reads more slowly and with more effort than peers and may make spelling errors, but generally understands grade-level texts when given time and a clear presentation.",
  "instrucciones": [
    {"id": "dislexia_leve.extension", "texto": "Keep the original length and complexity as far as possible; the main intervention is organisation, not reduction."},
    {"id": "dislexia_leve.estructura", "texto": "Improve organisation with headings, clearly separated paragraphs and visible connectors."},
    {"id": "dislexia_leve.frases", "texto": "Split only the longest or most complex sentences (more than about 25 words or several subordinate clauses); keep the rest as they are."},
    {"id": "dislexia_leve.formato", "texto": "Use a reader-friendly layout: left-aligned text, bold (not italics or underlining) for key terms and clear spacing between parts."},
    {"id": "dislexia_leve.terminos", "texto": "Highlight key technical terms in bold the first time they appear; add a brief explanation only if the original does not explain them.", "aplica_a": ["texto"]},
    {"id": "dislexia_leve.consignas", "texto": "Present multi-step instructions as separate numbered steps and put the action verb in bold.", "aplica_a": ["actividad"]},
    {"id": "dislexia_leve.produccion", "texto": "Keep the written production that the original requires, and offer optional supports such as a planning outline or a word bank with the technical terms.", "aplica_a": ["actividad"]}
  ]
}$json$::jsonb, 'Dislexia leve.'),

-- ---------------------------------------------------------
-- ETAPAS
-- ---------------------------------------------------------
('etapa', 'inicial', 1, $json${
  "etiqueta": "Early years / kindergarten (ages 3-5)",
  "descripcion": "Children are pre-readers or emerging readers. Materials are usually read aloud by an adult and responses are mostly oral, gestural or graphic.",
  "instrucciones": [
    {"id": "inicial.oral", "texto": "Write so that the material works when read aloud by an adult: short sentences, natural rhythm and repetition of key words."},
    {"id": "inicial.concreto", "texto": "Keep the examples of the original; if an example is abstract, reword it in concrete terms without changing what it illustrates."},
    {"id": "inicial.apoyo_visual", "texto": "Where an image, pictogram or real object would support understanding, mark it with a bracketed placeholder such as [image: a seed]. Do not describe images that are not needed."},
    {"id": "inicial.extension", "texto": "Keep the text brief and divided into very short parts.", "aplica_a": ["texto"]},
    {"id": "inicial.consignas", "texto": "Each instruction must be very short, contain one action and be answerable by pointing, choosing, drawing, moving or saying. Do not require reading or writing unless that is the objective of the activity.", "aplica_a": ["actividad"]}
  ]
}$json$::jsonb, 'Jardín / Nivel inicial.'),

('etapa', 'primaria_1', 1, $json${
  "etiqueta": "Primary school, first cycle (grades 1-3, ages 6-8)",
  "descripcion": "Students are beginning readers and writers who are consolidating decoding. They reason with concrete situations and can justify simple ideas.",
  "instrucciones": [
    {"id": "primaria_1.registro", "texto": "Use simple, clear language for beginning readers, with a warm but not childish tone."},
    {"id": "primaria_1.vocabulario", "texto": "Prefer familiar words and introduce each new subject word with a simple explanation."},
    {"id": "primaria_1.extension", "texto": "Keep the text brief; where a picture would clearly aid understanding, mark it with a bracketed placeholder such as [image: ...].", "aplica_a": ["texto"]},
    {"id": "primaria_1.consignas", "texto": "Use one action per instruction and simple response formats (circle, match, complete, draw and label, answer in one sentence). Keep the reasoning questions of the original ('why?', 'how do you know?').", "aplica_a": ["actividad"]}
  ]
}$json$::jsonb, 'Primaria – Primer ciclo (1.º a 3.º grado).'),

('etapa', 'primaria_2', 1, $json${
  "etiqueta": "Primary school, second cycle (grades 4-6, ages 9-11)",
  "descripcion": "Students are moving from learning to read to reading to learn. They handle longer texts, subject vocabulary and multi-step tasks, and are sensitive to being treated as younger than they are.",
  "instrucciones": [
    {"id": "primaria_2.registro", "texto": "Use clear language appropriate for ages 9-11. Avoid a babyish tone, diminutives or playful wording that would make the student feel treated as younger."},
    {"id": "primaria_2.estudio", "texto": "Use text features that build study skills: headings, subheadings and key terms in bold.", "aplica_a": ["texto"]},
    {"id": "primaria_2.consignas", "texto": "Activities may include several steps, but each step must be explicit and numbered. Keep the comparison, classification, cause-and-effect and justification tasks of the original.", "aplica_a": ["actividad"]}
  ]
}$json$::jsonb, 'Primaria – Segundo ciclo (4.º a 6.º grado).'),

('etapa', 'secundaria_basico', 1, $json${
  "etiqueta": "Lower secondary school (ages 12-14)",
  "descripcion": "Students work with disciplinary knowledge and academic language: definitions, processes, causes and consequences, and multiple perspectives. Materials must look and sound like secondary-school materials.",
  "instrucciones": [
    {"id": "secundaria_basico.registro", "texto": "Use a respectful, direct academic register. Do not use pictograms, playful language or simplifications typical of primary school."},
    {"id": "secundaria_basico.disciplina", "texto": "Keep the disciplinary language and the conceptual complexity expected at this stage."},
    {"id": "secundaria_basico.estudio", "texto": "Organise the text to support autonomous study: headings, key terms highlighted and logical connectors made visible.", "aplica_a": ["texto"]},
    {"id": "secundaria_basico.consignas", "texto": "Keep the cognitive verbs of the original (analyse, compare, explain, justify, argue) and add a brief clarification of what each verb requires the student to do.", "aplica_a": ["actividad"]}
  ]
}$json$::jsonb, 'Secundaria – Ciclo básico.'),

('etapa', 'secundaria_superior', 1, $json${
  "etiqueta": "Upper secondary school (ages 15-18)",
  "descripcion": "Students work with abstract concepts, argumentation, sources and academic writing, including pre-university or IB-style demands. The register is adult and academic.",
  "instrucciones": [
    {"id": "secundaria_superior.registro", "texto": "Keep an adult, academic register. Do not simplify concepts, arguments or academic vocabulary; adapt only the access barriers."},
    {"id": "secundaria_superior.complejidad", "texto": "Preserve the abstraction, argumentation, nuance and relationships between sources or perspectives present in the original."},
    {"id": "secundaria_superior.estudio", "texto": "Support long or dense texts with structure (headings, signposting of the argument, key terms highlighted) rather than by shortening the reasoning.", "aplica_a": ["texto"]},
    {"id": "secundaria_superior.consignas", "texto": "Preserve the level and the assessment criteria of the original tasks (analysis, evaluation, argumentation, synthesis). State the expected product explicitly (length, structure, criteria) instead of lowering the demand.", "aplica_a": ["actividad"]}
  ]
}$json$::jsonb, 'Secundaria – Ciclo superior.'),

-- ---------------------------------------------------------
-- TIPO DE MATERIAL
-- ---------------------------------------------------------
('material', 'texto', 1, $json${
  "etiqueta": "Study / reading text",
  "tarea": "Adapt the study or reading text provided below so that the student described can access it, while preserving its learning objectives and content.",
  "instrucciones": [
    {"id": "texto.accesibilidad", "texto": "Reading accessibility: adjust the decoding and fluency load (sentence length, word choice, density) as the profile and stage require."},
    {"id": "texto.estructura", "texto": "Structure: order the ideas logically and make the organisation of the text visible."},
    {"id": "texto.sintaxis", "texto": "Syntax: simplify sentence structure only as far as the profile and stage require."},
    {"id": "texto.vocabulario", "texto": "Vocabulary: keep the technical terms and clarify them; replace only non-technical words that are unnecessarily difficult."},
    {"id": "texto.organizacion", "texto": "Organisation: use headings, paragraphs and lists so that each part of the text has a clear function."},
    {"id": "texto.presentacion", "texto": "Presentation: use formatting that supports reading (headings, lists, bold for key terms)."}
  ],
  "prohibido": [
    {"id": "texto.no_actividades", "texto": "Do not create activities, questions, quizzes, exercises, comprehension checks or tasks of any kind, not even at the end of the text."},
    {"id": "texto.no_materiales", "texto": "Do not add separate materials such as worksheets, glossaries at the end, answer keys or notes for the teacher. Elements that are part of the adapted text itself (headings, a brief opening that anticipates the topic, an in-text explanation of a term) are allowed."}
  ],
  "formato_salida": [
    {"id": "texto.f_solo", "texto": "Return only the adapted text, ready to be given to the student."},
    {"id": "texto.f_markdown", "texto": "Use plain text with simple Markdown: # for headings, - for lists and **bold** for key terms. Do not use tables unless the original contains one."},
    {"id": "texto.f_sin_comentarios", "texto": "Do not write any introduction, explanation of the changes or comment before or after the adapted text."}
  ]
}$json$::jsonb, 'Texto de estudio / lectura.'),

('material', 'actividad', 1, $json${
  "etiqueta": "Activity / instructions / assessment",
  "tarea": "Adapt the activities, instructions or assessment provided below so that the student described can access and complete them, while preserving the cognitive skills and the assessment objectives of the original.",
  "instrucciones": [
    {"id": "actividad.consignas", "texto": "Instructions: rewrite each instruction so that it is clear, explicit and unambiguous."},
    {"id": "actividad.secuencia", "texto": "Sequencing: break complex tasks into ordered steps without removing any step that the original requires."},
    {"id": "actividad.lectura", "texto": "Reading load: reduce the amount of reading needed to understand what the task asks."},
    {"id": "actividad.produccion", "texto": "Written production: adjust the amount and form of writing as the profile requires, offering alternative response formats where appropriate, while assessing the same skill."},
    {"id": "actividad.formato_respuesta", "texto": "Response format: make clear where and how the student must answer (answer spaces, sentence frames, options)."},
    {"id": "actividad.organizacion", "texto": "Organisation: number the activities, keep one activity per block and keep the original order."},
    {"id": "actividad.habilidades", "texto": "Keep every activity of the original and the cognitive skill each one assesses: if an item asks the student to justify, compare or infer, the adapted item must still ask for it."}
  ],
  "prohibido": [
    {"id": "actividad.no_textos", "texto": "Do not create new reading texts, passages or stories, and do not add explanations of the subject content. A brief gloss of a technical term, or of what an instruction verb asks the student to do, is allowed. If an activity refers to a text that is not included, refer to it as the original does; do not write it."},
    {"id": "actividad.no_extra", "texto": "Do not add new activities, extension tasks, answer keys or complementary materials that were not requested."}
  ],
  "formato_salida": [
    {"id": "actividad.f_solo", "texto": "Return only the adapted activities, ready to be given to the student, in the same order as the original."},
    {"id": "actividad.f_markdown", "texto": "Use plain text with simple Markdown: number each activity, use - for lists and **bold** for action verbs or key terms. Mark answer spaces with a line of underscores (__________)."},
    {"id": "actividad.f_sin_comentarios", "texto": "Do not write any introduction, explanation of the changes or comment before or after the adapted activities."}
  ]
}$json$::jsonb, 'Actividad / consigna / evaluación.'),

-- ---------------------------------------------------------
-- IDIOMA
-- ---------------------------------------------------------
('idioma', 'es', 1, $json${
  "etiqueta": "Spanish",
  "idioma_salida": "Spanish",
  "cefr": null,
  "requiere_revision": false,
  "instrucciones": [
    {"id": "es.idioma", "texto": "The material is in Spanish, the language of instruction. Write the adapted material in Spanish and keep the regional variety of the original (for example, 'vos' and its verb forms if they appear)."},
    {"id": "es.sin_cefr", "texto": "Do not apply CEFR (foreign-language) levels: adjust the language only according to the student profile and the educational stage."}
  ]
}$json$::jsonb, 'Material en español: sin niveles CEFR.'),

('idioma', 'en_a1', 1, $json${
  "etiqueta": "English (CEFR A1)",
  "idioma_salida": "English",
  "cefr": "A1",
  "requiere_revision": false,
  "instrucciones": [
    {"id": "en_a1.idioma", "texto": "Write the adapted material in English. Do not translate any part into another language."},
    {"id": "en_a1.techo", "texto": "Keep the language at CEFR A1 or below: present simple, 'can', very common everyday words, short simple sentences and basic connectors (and, but, because)."},
    {"id": "en_a1.tecnicos", "texto": "Subject-specific terms do not count as a higher level: keep them, and if you clarify one, use A1 language."}
  ]
}$json$::jsonb, 'Inglés, nivel A1.'),

('idioma', 'en_a2', 1, $json${
  "etiqueta": "English (CEFR A2)",
  "idioma_salida": "English",
  "cefr": "A2",
  "requiere_revision": false,
  "instrucciones": [
    {"id": "en_a2.idioma", "texto": "Write the adapted material in English. Do not translate any part into another language."},
    {"id": "en_a2.techo", "texto": "Keep the language at CEFR A2 or below: present and past simple, 'going to', comparatives, common vocabulary, short sentences and frequent connectors (because, so, then, first, finally)."},
    {"id": "en_a2.tecnicos", "texto": "Subject-specific terms do not count as a higher level: keep them, and if you clarify one, use A2 language."}
  ]
}$json$::jsonb, 'Inglés, nivel A2.'),

('idioma', 'en_b1', 1, $json${
  "etiqueta": "English (CEFR B1)",
  "idioma_salida": "English",
  "cefr": "B1",
  "requiere_revision": false,
  "instrucciones": [
    {"id": "en_b1.idioma", "texto": "Write the adapted material in English. Do not translate any part into another language."},
    {"id": "en_b1.techo", "texto": "Keep the language at CEFR B1 or below: a range of common tenses (including present perfect), first and second conditionals, simple relative clauses (who, which, that) and connectors such as however, although and as a result."},
    {"id": "en_b1.tecnicos", "texto": "Subject-specific terms do not count as a higher level: keep them, and if you clarify one, use B1 language."}
  ]
}$json$::jsonb, 'Inglés, nivel B1.'),

('idioma', 'en_b2', 1, $json${
  "etiqueta": "English (CEFR B2)",
  "idioma_salida": "English",
  "cefr": "B2",
  "requiere_revision": false,
  "instrucciones": [
    {"id": "en_b2.idioma", "texto": "Write the adapted material in English. Do not translate any part into another language."},
    {"id": "en_b2.techo", "texto": "Keep the language at CEFR B2 or below. B2 structures (passive voice, reported speech, a wide range of connectors) may stay, but split long sentences when the profile requires it, and keep the academic vocabulary."},
    {"id": "en_b2.tecnicos", "texto": "Subject-specific terms do not count as a higher level: keep them."}
  ]
}$json$::jsonb, 'Inglés, nivel B2.'),

('idioma', 'en_c1', 1, $json${
  "etiqueta": "English (CEFR C1)",
  "idioma_salida": "English",
  "cefr": "C1",
  "requiere_revision": false,
  "instrucciones": [
    {"id": "en_c1.idioma", "texto": "Write the adapted material in English. Do not translate any part into another language."},
    {"id": "en_c1.techo", "texto": "The original uses complex, abstract language (CEFR C1). Do not raise it further. Adapt mainly structure and presentation; reword only the sentences whose complexity is an access barrier for the profile, and preserve the nuance of the argument."},
    {"id": "en_c1.tecnicos", "texto": "Subject-specific and academic terms do not count as a higher level: keep them."}
  ]
}$json$::jsonb, 'Inglés, nivel C1.'),

('idioma', 'en_c2', 1, $json${
  "etiqueta": "English (CEFR C2)",
  "idioma_salida": "English",
  "cefr": "C2",
  "requiere_revision": false,
  "instrucciones": [
    {"id": "en_c2.idioma", "texto": "Write the adapted material in English. Do not translate any part into another language."},
    {"id": "en_c2.techo", "texto": "The original uses highly complex language (CEFR C2). Adapt mainly structure and presentation; reword only the sentences whose complexity is an access barrier for the profile, preserving precision and nuance."},
    {"id": "en_c2.tecnicos", "texto": "Subject-specific and academic terms do not count as a higher level: keep them."}
  ]
}$json$::jsonb, 'Inglés, nivel C2.'),

('idioma', 'en_sin_nivel', 1, $json${
  "etiqueta": "English (CEFR level not estimated)",
  "idioma_salida": "English",
  "cefr": null,
  "requiere_revision": true,
  "nota_revision": "The teacher should check the linguistic level of the adapted material.",
  "instrucciones": [
    {"id": "en_sin_nivel.idioma", "texto": "Write the adapted material in English. Do not translate any part into another language."},
    {"id": "en_sin_nivel.techo", "texto": "The CEFR level of the original could not be estimated reliably. Do not assume a level: keep the grammar and general vocabulary of the adapted material at or below the level of the original."}
  ]
}$json$::jsonb, 'Inglés con nivel no estimable (material muy corto).'),

('idioma', 'indeterminado', 1, $json${
  "etiqueta": "Language not identified with confidence",
  "idioma_salida": "the same language as each part of the original",
  "cefr": null,
  "requiere_revision": true,
  "nota_revision": "The teacher should check that each part of the adapted material keeps its original language.",
  "instrucciones": [
    {"id": "indeterminado.cada_parte", "texto": "The material may contain Spanish and English, or its language could not be identified with confidence. Keep each part in its original language; do not translate anything and do not unify the languages."},
    {"id": "indeterminado.sin_cefr", "texto": "Do not assign or apply a CEFR level. For parts in English, keep the language at or below the level of the original; for parts in Spanish, adjust only according to the profile and stage."}
  ]
}$json$::jsonb, 'Idioma mixto o no identificable: requiere revisión.')

ON CONFLICT (categoria, clave, version) DO NOTHING;
