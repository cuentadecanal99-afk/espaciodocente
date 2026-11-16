# Generador de Adaptaciones

Pestaña **Adaptaciones** de Espacio Docente. El docente elige el perfil del estudiante, la etapa educativa y el tipo de material, y pega el material original. La herramienta arma un prompt completo, en inglés, para copiar y pegar en una IA externa (Claude, ChatGPT, Gemini, etc.). **No llama a ninguna IA.**

## Qué se modificó

| Archivo | Cambio |
|---|---|
| `index.html` | La pestaña "Adaptaciones" deja de estar en pausa ("Pronto") y carga `adaptaciones.html` en un iframe, igual que Secuencias, Tareas y Rúbrica. |
| `adaptaciones.html` | La herramienta: formulario (perfil, etapa, tipo de material y material original) y resultado (prompt editable, Copiar prompt y Generar otro prompt). Usa la sesión de Espacio Docente. |
| `adaptaciones-prompt.js` | El armado del prompt: detecta el idioma, estima el CEFR, valida y combina las reglas. No contiene reglas pedagógicas. |
| `supabase/supabase-migration-adaptaciones.sql` | Crea la tabla `adaptacion_reglas`, su validación y las reglas iniciales (versión 1). |
| `.github/scripts/pruebas.mjs` y `muestras-adaptaciones.mjs` | Pruebas automáticas: las 5 combinaciones pedidas y los controles de calidad. |

`indexADAPT.html` (el prototipo viejo) y las tablas `perfiles_dislexia` y `niveles_idioma` no se usan ni se tocaron.

## Estructura en Supabase

Tabla `public.adaptacion_reglas`. Cada fila es **una regla**:

| Columna | Qué guarda |
|---|---|
| `categoria` | `general`, `perfil`, `etapa`, `material` o `idioma` |
| `clave` | El identificador de la regla dentro de la categoría (ver abajo) |
| `version` | Número de versión (1, 2, 3...) |
| `activa` | `true` es la versión que se usa. Puede haber **una sola** activa por categoría y clave. |
| `contenido` | El JSON con las instrucciones |
| `notas` | Comentario libre para quien administra |

Identificadores (`clave`):

- **general:** `general`
- **perfil:** `tea`, `dislexia_severa`, `dislexia_leve`
- **etapa:** `inicial`, `primaria_1`, `primaria_2`, `secundaria_basico`, `secundaria_superior`
- **material:** `texto`, `actividad`
- **idioma:** `es`, `en_a1`, `en_a2`, `en_b1`, `en_b2`, `en_c1`, `en_c2`, `en_sin_nivel` (inglés demasiado corto para estimar el nivel), `indeterminado` (mezcla de idiomas o idioma no identificado)

Cada prompt usa **exactamente 5 reglas**, una por categoría, elegidas en el momento según lo que seleccionó el docente. No hay combinaciones guardadas de antemano.

### Permisos

- Solo los docentes con sesión iniciada pueden leer, y solo las reglas activas.
- Nadie puede escribir desde la página. Las reglas se editan desde el dashboard de Supabase.

## Formato del JSON (`contenido`)

Todas las reglas tienen:

```json
{
  "etiqueta": "Nombre que aparece en el prompt (en inglés)",
  "instrucciones": [
    { "id": "<clave>.<nombre>", "texto": "Instrucción en inglés" }
  ]
}
```

- **`id`:** tiene que empezar con la clave de la regla y un punto, por ejemplo `tea.literal`. No se puede repetir.
- **`aplica_a`:** solo en reglas de **perfil** y **etapa**. Se agrega `"aplica_a": ["texto"]` o `"aplica_a": ["actividad"]` a una instrucción que vale solo para ese tipo de material. Sin `aplica_a`, la instrucción vale para los dos.
- **`reemplaza`:** opcional, en cualquier regla menos la general. Es una lista de ids de instrucciones generales que esta regla sustituye, por ejemplo `["general.vocabulario_tecnico"]`. Sirve para afinar una regla general sin que el prompt tenga dos instrucciones que se contradigan. Las restricciones no se pueden reemplazar.

Campos extra por categoría:

| Categoría | Campos obligatorios |
|---|---|
| general | `rol`, `precedencia` y `restricciones` (lista de instrucciones que nunca se pueden pasar por alto) |
| perfil, etapa | `descripcion` |
| material | `tarea`, `prohibido` (lista) y `formato_salida` (lista) |
| idioma | `idioma_salida`, `cefr` (`"A1"`...`"C2"` solo en `en_a1`...`en_c2`; `null` en las demás) y `requiere_revision` (`true`/`false`). Si `requiere_revision` es `true`, también `nota_revision`. |

La base **rechaza al guardar** cualquier JSON que no cumpla este formato (función `adaptacion_contenido_valido`). Así, una regla mal cargada nunca llega a los docentes.

## Cómo editar una regla (con versión)

Para no perder la versión anterior, se crea una versión nueva y se desactiva la vieja **en el mismo paso** (SQL Editor):

```sql
begin;
update public.adaptacion_reglas set activa = false
 where categoria = 'perfil' and clave = 'tea' and activa;

insert into public.adaptacion_reglas (categoria, clave, version, contenido, notas)
select categoria, clave, version + 1,
       jsonb_set(contenido, '{instrucciones}', contenido->'instrucciones' || '[{"id":"tea.nueva","texto":"New instruction in English."}]'),
       'Agrego instrucción X'
  from public.adaptacion_reglas
 where categoria = 'perfil' and clave = 'tea'
 order by version desc limit 1;
commit;
```

Para corregir solo un error de tipeo, también se puede editar el `contenido` directamente en el Table Editor.

**Volver a una versión anterior:** desactivar la actual y activar la anterior, también en una transacción.

## Cómo se arma el prompt

1. Se valida que estén el perfil, la etapa, el tipo de material y el material original.
2. Se detecta el idioma del material: español, inglés o indeterminado (mezcla o poca confianza).
3. Si es inglés, se estima el nivel CEFR **del material**, no del alumno. La estimación es conservadora:
   - Usa el largo de las oraciones, las estructuras gramaticales y las palabras largas que no son técnicas.
   - Ante la duda, queda el nivel más bajo.
   - Los términos disciplinares no suben el nivel.
   - Con menos de unas 40 palabras no estima nada y usa `en_sin_nivel`.
4. Se traen de Supabase las 5 reglas activas y se controla lo siguiente:
   - que no falte ninguna;
   - que no haya dos versiones activas;
   - que no se mezclen perfiles, ni texto con actividad;
   - que no se aplique CEFR al español;
   - que no haya ids repetidos;
   - que `reemplaza` apunte a una regla que exista.

   **Si algo falla, no se genera el prompt** y se muestra qué regla falta o está mal.
5. Se arma el prompt en este orden: rol, tarea, perfil, etapa, idioma, precedencia, principios generales, instrucciones del perfil, de la etapa, del tipo de material y del idioma, restricciones, material original (sin modificar, entre delimitadores) y formato de respuesta.

## Pruebas

```
node .github/scripts/pruebas.mjs
```

La sección 5 arma los prompts de las 5 combinaciones pedidas con las reglas de la migración. Verifica que cada uno:

- tenga todas las secciones;
- detecte bien el idioma y el nivel;
- no mezcle reglas de otro perfil ni del otro tipo de material;
- no repita instrucciones;
- conserve intacto el material original.

Además prueba los errores de configuración. Corre sola en GitHub con cada push.

**Importante:** si editás reglas en Supabase, las pruebas siguen usando las de la migración. Ante un cambio grande, conviene actualizar también el archivo de migración.
