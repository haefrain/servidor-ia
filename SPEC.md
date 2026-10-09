# Spec — Servidor de IA local

Versión 2026-10-09 · Efraín Camilo Hernández Arias

> **Para Claude Code:** ejecuta este spec fase por fase, en orden. Al final de cada fase, detente, entrega el reporte que pide la sección "Reportar al terminar" y espera confirmación antes de seguir. Si un paso falla o un supuesto no se cumple (nombre de repo, versión, hardware distinto), repórtalo en vez de improvisar.

## Contexto y objetivo

Convertir el PC (i5-12600K, RTX 3070 Ti, Ubuntu Server limpio en el SSD de 512 GB) en un servidor de inferencia dedicado al que la orquesta multiagente de Efra (Fable orquesta; Opus, Sonnet, Sol y Gemini Flash trabajan) pueda delegar tareas repetitivas sin gastar tokens de pago. El modelo local entra como **un proveedor OpenAI-compatible más**, con rol de *worker*: ejecuta bajo instrucción cerrada, nunca planea ni decide arquitectura. Se usa para los proyectos personales de VantLabs, que son los que más tokens consumen.

Hay dos modos que no coexisten (8 GB de VRAM) y un script los alterna:

| Modo | Modelo | Dónde vive | Para qué |
| --- | --- | --- | --- |
| Diurno | Qwen3.5-9B (o Granite 4.1-8B) | 100% VRAM, 4 slots concurrentes | Hooks, clasificación, resúmenes, 4 agentes a la vez |
| Por lotes / nocturno | Qwen3.6-35B-A3B (MoE) | Atención en VRAM, expertos en RAM, 1–2 slots | Tickets pequeños con spec cerrado, tests, migraciones; Claude revisa el PR después |

**Qué se delega al modelo local** (y qué no):

| Tarea | Local | Claude |
| --- | --- | --- |
| Mensajes de commit y títulos de PR | ✔ | |
| Resumir/explicar errores de tsc, lint y tests | ✔ | |
| Clasificar cambios (toca auth, pagos, datos sensibles: sí/no + razón) | ✔ | |
| Resumir archivos largos o logs a ≤200 tokens | ✔ | |
| Validar que una spec cumple la plantilla SDD (checklist) | ✔ | |
| Primera pasada del patrón Writer/Reviewer | ✔ | |
| Escribir o refactorizar código de producción | | ✔ |
| Decisiones de arquitectura | | ✔ |
| Cualquier tarea con contexto > 32K tokens | | ✔ |

## Hardware y restricciones

La VRAM de 8 GB es el límite que gobierna todo: solo cabe un modelo de ~9B en Q4 con contexto moderado, y uno a la vez.

| Componente | Valor | Implicación |
| --- | --- | --- |
| GPU | RTX 3070 Ti, 8 GB GDDR6X (~608 GB/s) | Pesos ≤ 6 GB en Q4_K_M; el resto es KV cache |
| CPU | i5-12600K (6P + 4E, AVX2, sin AVX-512) | Hilos de llama.cpp fijados a P-cores: `-t 6` |
| RAM | 32 GB DDR4-3200 (~50 GB/s) | Modo diurno usa ~2 GB; modo híbrido ~20 GB |
| Discos | SSD 512 GB → Ubuntu Server (arranque por defecto); SSD 1 TB → Kubuntu existente, intacto, segundo arranque | ~55 GB usados en el de 512; nada se toca en el de 1 TB |
| SO | Ubuntu Server 26.04 LTS, sin escritorio | ~0.5 GB de RAM en reposo; drivers NVIDIA + CUDA |
| Red | 500/500 Mbps, Tailscale | El Mac llega al PC por IP de Tailscale, sin abrir puertos |
| Fallback | Mac mini M4 base, 24 GB | Solo para el 9B cuando el PC esté apagado (~25 tok/s); el 35B no cabe mientras se trabaja |

**Presupuesto de VRAM por modelo (Q4_K_M, KV cache en q8_0):**

| Modelo | Pesos | Contexto objetivo | KV cache aprox. | Total | Margen |
| --- | --- | --- | --- | --- | --- |
| Qwen3.5-9B | ~5.5 GB | 32K total (4×8K) | ~1.6 GB | ~7.3 GB | ~0.5 GB |
| Granite 4.1-8B | ~5.0 GB | 32K total (4×8K) | ~2.0 GB | ~7.2 GB | ~0.6 GB |

Si un modelo no arranca con esos valores, Claude Code debe bajar a `-np 2` / `-c 16384` y reportarlo, nunca pasar capas a CPU en modo diurno (en este hardware cae a 1–2 tok/s).

**Restricciones adicionales:**

- El PC es servidor dedicado: sin escritorio, sin VM, sin otros servicios pesados. Toda la VRAM y casi toda la RAM quedan para el modelo.
- En modo híbrido (20 GB de RAM para el modelo) no debe correr nada más que consuma RAM; Claude Code debe verificar `free -g` antes de arrancarlo.
- `nvidia-smi` no debe listar procesos distintos de `llama-server`.
- El Kubuntu del disco de 1 TB no se monta ni se toca; es solo un segundo arranque de emergencia.

## Decisiones de diseño

Arquitectura: Claude Code y la orquesta en el Mac → Tailscale → `llama-server` (CUDA, systemd) en el PC → RTX 3070 Ti con un solo modelo cargado; `switch-model.sh` cambia la unidad systemd.

| Decisión | Elegido | Descartado | Por qué |
| --- | --- | --- | --- |
| Runtime | llama.cpp (`llama-server`) compilado con CUDA | Ollama | Control fino de hilos, KV cache cuantizado y flags por modelo; Ollama es más cómodo pero rinde peor en este hardware |
| Modelo principal | Qwen3.5-9B Instruct, Q4_K_M | Qwen3-8B, Qwen2.5-Coder-7B | Mejor tool calling y código del tier 8 GB; thinking apagado por defecto |
| Modelo alterno | Granite 4.1-8B Instruct, Q4_K_M | Gemma 4 12B | Sin cadena de razonamiento: latencia predecible para hooks; Gemma deja muy poco contexto en 8 GB |
| Carga | Un modelo a la vez, unidades systemd separadas | Dos modelos simultáneos | No caben dos en 8 GB |
| API | OpenAI-compatible (`/v1/chat/completions`) | API propia | Cualquier cliente, SDK o MCP la consume sin adaptación |
| Red | Tailscale, bind a la IP de Tailscale | Exponer puerto en LAN/Internet | Cero puertos abiertos; el Mac y la tablet ya están en la tailnet |
| Integración | MCP server mínimo + hooks de Claude Code | Reemplazar subagentes de Claude Code | Claude Code no enruta subagentes a otro proveedor; MCP y hooks son el camino soportado |

## Fase 1 — Preparación del sistema

Al terminar, Ubuntu Server arranca desde el SSD de 512 GB, `nvidia-smi` ve la 3070 Ti sin procesos, `nvcc` compila, Tailscale está conectado y Claude Code corre en el PC con la cuenta Max.

**Parte A — a mano, Efra.** Está automatizada en `bootstrap.sh` de este repo (ver README). Resumen de lo que hace: actualiza el sistema, instala Tailscale, instala Claude Code, clona este repo en `~/dev/servidor-ia` y deja las instrucciones para el login. Lo único manual es la instalación de Ubuntu Server y el login de Claude Code.

**Parte B — Claude Code:**

- [ ] Verificar que el arranque es el SSD de 512 (`lsblk`, `findmnt /`) y que el de 1 TB está sin montar
- [ ] Instalar driver NVIDIA propietario recomendado: `sudo ubuntu-drivers install` (o `nvidia-driver-5xx-server` si `ubuntu-drivers devices` lo lista); reiniciar
- [ ] Verificar: `nvidia-smi` muestra la RTX 3070 Ti con 8192 MiB y lista de procesos vacía
- [ ] Instalar CUDA toolkit desde el repo oficial de NVIDIA (no el de apt genérico). Si NVIDIA aún no publica repo para Ubuntu 26.04, usar el de 24.04 (`ubuntu2404`), que es compatible; verificar `nvcc --version`
- [ ] Instalar dependencias de compilación: `build-essential cmake git curl libcurl4-openssl-dev python3-pip pipx`
- [ ] Instalar `huggingface_hub` CLI (`pipx install "huggingface_hub[cli]"`) para descargar modelos
- [ ] Crear usuario de servicio sin login: `sudo useradd -r -s /usr/sbin/nologin -d /opt/llm llm`
- [ ] Crear estructura: `/opt/llm/{bin,models,logs,conf}` propiedad de `llm:llm`
- [ ] Activar Wake-on-LAN en BIOS (Efra) y en Linux (`ethtool -s <iface> wol g`, persistente vía netplan o systemd), anotar la MAC
- [ ] Fijar el driver NVIDIA para que un `apt upgrade` no lo rompa: `sudo apt-mark hold nvidia-driver-*`
- [ ] Opcional: `sudo nvidia-smi -pl 220` persistente (unidad systemd) para limitar consumo a 220 W
- [ ] Dejar `unattended-upgrades` solo para parches de seguridad, sin reinicios automáticos

**Reportar al terminar:** salida de `nvidia-smi`, `nvcc --version`, `tailscale ip -4`, y la MAC de la interfaz de red.

## Fase 2 — llama.cpp con CUDA y modelos

Al terminar, `llama-server` arranca cada modelo 100% en GPU y responde en `/v1/chat/completions`.

**Compilación**

- [ ] `git clone https://github.com/ggml-org/llama.cpp /opt/llm/src` (último tag estable, no `master`)
- [ ] `cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 -DLLAMA_CURL=ON` (86 = Ampere, 3070 Ti)
- [ ] `cmake --build build --config Release -j 6`; copiar `llama-server` y `llama-bench` a `/opt/llm/bin`
- [ ] Verificar: `llama-server --version` y que el binario enlaza con CUDA (`ldd | grep cuda`)

**Descarga de modelos** (GGUF Q4_K_M; verificar en Hugging Face el repo exacto y el hash, los nombres pueden variar)

| Modelo | Repo sugerido | Archivo | Tamaño aprox. |
| --- | --- | --- | --- |
| Qwen3.5-9B Instruct | `unsloth/Qwen3.5-9B-Instruct-GGUF` o el oficial `Qwen/...-GGUF` | `*-Q4_K_M.gguf` | ~5.5 GB |
| Granite 4.1-8B Instruct | `unsloth/granite-4.1-8b-GGUF` | `*-Q4_K_M.gguf` | ~5.0 GB |

- [ ] Descargar con `huggingface-cli download <repo> <archivo> --local-dir /opt/llm/models`
- [ ] Si Qwen3.5-9B viene con proyector de visión (`mmproj-*.gguf`), no descargarlo: solo texto

**Parámetros de arranque** (validar con `llama-bench` antes de fijarlos)

| Flag | Qwen3.5-9B | Granite 4.1-8B | Por qué |
| --- | --- | --- | --- |
| `-ngl` | 99 | 99 | Todas las capas en GPU |
| `-c` | 32768 | 32768 | Contexto total; se reparte entre slots (8K cada uno con `-np 4`) |
| `-np` | 4 | 4 | Cuatro agentes de la orquesta en paralelo con continuous batching; bajar a 2 si no cabe |
| `-ctk / -ctv` | q8_0 / q8_0 | q8_0 / q8_0 | KV cache cuantizado, ahorra ~50% de VRAM del cache |
| `-fa` | on | on | Flash attention, menos VRAM y más velocidad |
| `-t` | 6 | 6 | Solo P-cores |
| `-b / -ub` | 2048 / 512 | 2048 / 512 | Batch de prompt; subir si sobra VRAM |
| `--jinja` | sí | sí | Plantilla de chat nativa con tool calling |
| `--reasoning-budget` | 0 | n/a | Qwen sin thinking por defecto; el cliente lo activa por request |
| `--host / --port` | IP Tailscale / 8080 | IP Tailscale / 8080 | Nunca `0.0.0.0` |
| `--api-key` | desde `/opt/llm/.env` | igual | Clave larga aleatoria; los clientes la mandan como `Authorization: Bearer` |

- [ ] Correr `llama-bench -m <modelo> -ngl 99 -t 6 -fa 1` y registrar pp512 y tg128 de cada modelo
- [ ] Arrancar cada uno a mano, probar con `curl` un chat simple y uno con `tools` definido; confirmar que devuelve `tool_calls` bien formado

**Reportar al terminar:** tabla con tokens/s de prompt y generación por modelo, VRAM usada según `nvidia-smi` con el modelo cargado, y la respuesta cruda del test de tool calling.

## Fase 3 — Servicio systemd y cambio de modelo

Al terminar, el modelo arranca solo al encender el PC y cambiarlo toma un comando y menos de 20 segundos.

**Estructura**

```
/opt/llm/
  bin/llama-server
  bin/switch-model.sh
  models/*.gguf
  conf/qwen.env        # flags de Qwen3.5-9B
  conf/granite.env     # flags de Granite 4.1-8B
  conf/hibrido.env     # flags del modo híbrido (Fase 7)
  .env                 # LLM_API_KEY, LLM_BIND_IP
  logs/
```

**Unidades**

- [ ] Una plantilla `llm@.service` que lee `/opt/llm/conf/%i.env` y arranca `llama-server` con esos flags; `User=llm`, `Restart=on-failure`, `RestartSec=5`
- [ ] `Conflicts=` entre instancias para que systemd nunca tenga dos cargadas (ej. `llm@qwen` declara `Conflicts=llm@granite.service llm@hibrido.service` y así en las otras)
- [ ] `WantedBy=multi-user.target` solo en la instancia por defecto: `sudo systemctl enable llm@qwen`
- [ ] Logs a `journalctl -u llm@qwen` y copia rotada en `/opt/llm/logs/` (logrotate semanal, 4 copias)

**Script `switch-model.sh <qwen|granite|hibrido>`**

1. `systemctl stop` de la instancia activa
2. `systemctl start` de la pedida
3. Esperar hasta que `GET /health` responda 200 (timeout 60 s diurno, 180 s híbrido)
4. Imprimir modelo activo, VRAM usada y tokens/s del último bench

- [ ] Permitir que el usuario del Mac lo invoque por SSH sin contraseña: regla `sudoers` limitada a ese script
- [ ] Exponer también `GET /v1/models` para que el cliente sepa qué modelo está cargado sin SSH

**Reportar al terminar:** salida de `systemctl status llm@qwen`, tiempo medido de `switch-model.sh granite` y de vuelta, y confirmación de que tras un reinicio del PC el modelo por defecto queda arriba.

## Fase 4 — Acceso desde el Mac

Al terminar, desde el Mac un `curl` con la API key responde en menos de 1 s de latencia de red y ningún puerto del PC es visible fuera de la tailnet.

Esta fase la ejecuta Claude Code **en el Mac**, no en el PC.

- [ ] Confirmar que el Mac ve al PC: `tailscale ping <hostname-pc>` y `tailscale status`
- [ ] Guardar en el Mac `~/.config/local-llm/.env` con `LOCAL_LLM_URL=http://<ip-tailscale>:8080/v1` y `LOCAL_LLM_API_KEY=...` (permisos 600)
- [ ] Probar: `curl $LOCAL_LLM_URL/models -H "Authorization: Bearer $LOCAL_LLM_API_KEY"` devuelve el modelo cargado
- [ ] Probar un chat completo con `tools` y confirmar `tool_calls` en la respuesta
- [ ] Verificar desde fuera de la tailnet (datos móviles del celular) que `http://<ip-lan-pc>:8080` NO responde
- [ ] Crear alias en el Mac: `llm-switch qwen|granite|hibrido` → `ssh pc sudo /opt/llm/bin/switch-model.sh $1`
- [ ] Crear alias `llm-wake` → `wakeonlan <MAC>` para encender el PC cuando esté apagado
- [ ] Opcional: Tailscale ACL que solo deje al Mac y a la tablet llegar al puerto 8080 del PC

**Reportar al terminar:** latencia medida del `curl` (`time`), y confirmación del test negativo desde fuera de la tailnet.

## Fase 5 — Integración con Claude Code

Al terminar, Claude Code en el Mac tiene un MCP server `local-llm` con tres herramientas y dos hooks que usan el modelo local sin intervención manual.

Esta fase también se ejecuta **en el Mac**, en un repo propio (`~/dev/local-llm-mcp`), fuera de los repos de ReclamaAI y BUK; luego se conecta a cada proyecto desde su `.claude/settings.json`.

**MCP server `local-llm`** (Node/TypeScript, stdio, OpenAI SDK apuntando a `LOCAL_LLM_URL`)

| Herramienta | Entrada | Salida | Modelo sugerido |
| --- | --- | --- | --- |
| `summarize` | texto o ruta de archivo, `max_tokens` (default 200) | resumen en español | Granite |
| `classify_change` | diff de git | JSON `{touches_auth, touches_payments, touches_pii, risk: low/medium/high, reason}` | Granite |
| `review_draft` | contenido + checklist (ej. plantilla SDD) | lista de hallazgos con línea y severidad | Qwen (thinking on) |

- [ ] Cada herramienta recorta la entrada a 12K tokens y avisa si truncó
- [ ] Timeout de 60 s por llamada; si el servidor no responde, la herramienta devuelve error claro y Claude sigue sin ella
- [ ] Leer `GET /v1/models` al arrancar para saber qué modelo está cargado; si la herramienta prefiere el otro, lo usa igual y lo anota en la respuesta (no cambia el modelo solo)
- [ ] Registrar en `~/.claude.json` (scope user) para que esté en todos los proyectos

**Hooks** (scripts en `~/.claude/hooks/`, llamados desde `settings.json`)

| Hook | Evento | Qué hace | Modelo |
| --- | --- | --- | --- |
| `commit-msg` | `PreToolUse` en `Bash` cuando el comando es `git commit` sin `-m` | Genera el mensaje con el diff staged y lo inyecta con `-m` (formato conventional commits, español) | Granite |
| `explain-errors` | `PostToolUse` en `Bash` cuando la salida contiene errores de `tsc`, `eslint` o `vitest/jest` | Resume los errores a ≤10 líneas y los agrega al contexto en vez de la salida cruda | Granite |

- [ ] Los hooks fallan en silencio (exit 0 con salida vacía) si el servidor local no está arriba; nunca bloquean a Claude Code
- [ ] Variable `LOCAL_LLM_DISABLED=1` apaga MCP y hooks sin tocar config
- [ ] Documentar en el `CLAUDE.md` global cuándo Claude Code debe preferir `local-llm` sobre hacerlo él mismo (la tabla de la sección Contexto)

**Candidatos para después** (no en este spec): hook `Stop` que valide specs contra la plantilla SDD; primera pasada del Writer/Reviewer en ReclamaAI.

**Reportar al terminar:** transcript de un `git commit` sin `-m` con el mensaje generado, y un ejemplo de `explain-errors` antes/después.

## Fase 6 — Benchmark A/B

Al terminar, hay una decisión documentada de qué modelo queda por defecto y cuál se usa para cada herramienta.

Las pruebas usan material real: diffs y errores recientes de ReclamaAI y BUK, nunca ejemplos inventados.

**Tareas de prueba** (5 muestras por tarea, mismas muestras para ambos modelos)

| Tarea | Muestra | Cómo se califica |
| --- | --- | --- |
| Commit message | 5 diffs staged reales | ¿Lo usarías sin editar? sí / casi / no |
| Explicar errores | 5 salidas reales de tsc/eslint/tests | ¿Identifica la causa raíz? sí / no |
| Clasificar cambio | 5 diffs, 2 de ellos tocando auth o pagos | Aciertos sobre 5; JSON válido sobre 5 |
| Resumen de archivo | 5 archivos de 300–800 líneas | ¿Omite algo importante? sí / no |
| Revisión contra checklist | 3 specs SDD, una con 2 errores sembrados | Errores sembrados encontrados; falsos positivos |

**Métricas por modelo**

- Calidad: tabla de resultados por tarea (arriba)
- Velocidad: latencia total por llamada (p50 y p95) y tokens/s de generación
- Confiabilidad: % de `tool_calls` / JSON válidos sin reintento
- VRAM pico según `nvidia-smi` durante la prueba

**Regla de decisión**

1. Si un modelo gana en calidad en 4 de 5 tareas, queda por defecto
2. Si empatan, gana el más rápido en p95
3. Una tarea puede quedar asignada al otro modelo si la diferencia de calidad ahí es clara; se anota en la tabla de herramientas de la Fase 5

**Reportar al terminar:** las dos tablas llenas y la decisión escrita en una línea por herramienta.

## Fase 7 — Modo híbrido por lotes (condicionada)

Solo se ejecuta si las Fases 1–6 pasan y el 9B demostró ser útil. Al terminar, hay un modelo MoE de ~35B corriendo con expertos en RAM, un bench real en esta DDR4 y una decisión sobre si vale la pena frente a comprar una GPU de 24 GB.

**Modelo**

| Candidato | Tamaño Q4 | Por qué |
| --- | --- | --- |
| Qwen3.6-35B-A3B Instruct (preferido) | ~20 GB | MoE con ~3B activos; el único tipo de modelo que sobrevive a leer pesos desde DDR4 |
| Qwen3-Coder-30B-A3B Instruct (alterno) | ~18 GB | Entrenado para agentic coding; usar si el 3.6 no está en GGUF o falla la plantilla |

- [ ] Verificar en Hugging Face el repo y el GGUF Q4_K_M exactos; descargar a `/opt/llm/models`
- [ ] Crear `/opt/llm/conf/hibrido.env` y la instancia `llm@hibrido` con `Conflicts=` contra las otras dos

**Flags del modo híbrido**

| Flag | Valor | Por qué |
| --- | --- | --- |
| `-ngl` | 99 | Todo lo que no sea experto va a GPU |
| `--n-cpu-moe` (o `-ot ".ffn_.*_exps.=CPU"`) | todos los expertos | Expertos en RAM, atención y capas compartidas en VRAM |
| `-c` | 49152 | Hay más VRAM libre para KV porque los pesos pesados están en RAM |
| `-np` | 2 | El batching no ayuda cuando el cuello es la RAM |
| `-t` | 6 | P-cores |
| `-ctk / -ctv / -fa` | q8_0 / q8_0 / on | Igual que el diurno |
| `--mlock` | sí | Evita que el kernel pagine los expertos a disco |

**Bench y prueba real**

- [ ] `llama-bench` con los mismos flags: registrar pp512, tg128 y RAM/VRAM pico
- [ ] Tres tickets reales de proyectos personales con spec cerrado (ej. un endpoint CRUD con tests, una migración, un refactor mecánico), ejecutados con un harness agéntico que acepte endpoint OpenAI local, en loop: implementar → correr tests → reintentar con el error → máx. 5 intentos → commit en branch
- [ ] Claude (Fable/Opus) revisa los tres PR y califica: ¿mergeable sin cambios / con cambios menores / rehacer?

**Regla de decisión**

1. Si 2 de 3 PR salen mergeables o con cambios menores, el modo híbrido queda activo para lotes nocturnos
2. Si tg < 15 tok/s o pp < 100 tok/s en el bench, documentar y evaluar una GPU de 24 GB (RTX 3090 usada) antes de insistir
3. Si 0 de 3 PR sirven, el modo híbrido se descarta y el PC queda solo en modo diurno

**Reportar al terminar:** tabla del bench, los tres PR con la calificación de Claude, y la decisión en una línea.

## Criterios de aceptación

| # | Criterio | Fase |
| --- | --- | --- |
| 1 | Ubuntu Server arranca desde el SSD de 512; el de 1 TB está intacto y sin montar | 1 |
| 2 | `nvidia-smi` y `nvcc` funcionan; `nvidia-smi` no lista procesos en reposo | 1 |
| 3 | Claude Code corre en el PC con la cuenta Max (`claude doctor` sin errores) | 1 |
| 4 | Cada modelo diurno carga 100% en GPU (`-ngl 99`, 0 capas en CPU) con `-np 4` y 32K total, o `-np 2` documentado | 2 |
| 5 | Qwen3.5-9B genera ≥ 40 tok/s y Granite 4.1-8B ≥ 45 tok/s en `llama-bench` tg128 con 1 request | 2 |
| 6 | Con 4 requests simultáneos, cada uno recibe ≥ 20 tok/s | 2 |
| 7 | Un request con `tools` devuelve `tool_calls` válido en ambos modelos | 2 |
| 8 | El modelo por defecto arranca solo tras reiniciar el PC | 3 |
| 9 | `switch-model.sh` cambia de modelo en < 20 s (diurno) y nunca deja dos cargados | 3 |
| 10 | Desde el Mac, `curl` a `/v1/models` responde con API key; sin API key responde 401 | 4 |
| 11 | El puerto 8080 no responde fuera de la tailnet | 4 |
| 12 | MCP `local-llm` aparece en Claude Code con sus 3 herramientas y responde | 5 |
| 13 | `git commit` sin `-m` produce un mensaje generado localmente | 5 |
| 14 | Con el PC apagado, Claude Code sigue funcionando sin errores visibles | 5 |
| 15 | Tablas del A/B llenas y decisión escrita por herramienta | 6 |
| 16 | Modo híbrido: bench registrado, 3 PR calificados por Claude y decisión escrita | 7 |

## Fuera de alcance y riesgos

**Fuera de alcance de este spec**

- Modelos densos de más de ~12B (en DDR4 no son viables)
- Reemplazar a Fable/Opus como orquestador o planner por el modelo local
- Fine-tuning o embeddings (RAG) locales
- Exponer el servidor a clientes fuera de la tailnet
- Interfaz web de chat (Open WebUI o similar)
- Usar el PC como estación de trabajo o para la VM del trabajo de España

**Riesgos**

| Riesgo | Señal | Mitigación |
| --- | --- | --- |
| El GGUF de Qwen3.5-9B o del 35B-A3B no existe con ese nombre o la plantilla de chat falla en llama.cpp | Error al cargar o `tool_calls` vacío | Buscar el repo oficial o de unsloth/bartowski; si llama.cpp aún no soporta la arquitectura, usar Qwen3-8B 2507 o Qwen3-Coder-30B-A3B como puente y documentarlo |
| 32K de contexto con `-np 4` no cabe en el diurno | OOM al arrancar | Bajar a `-np 2` con `-c 16384`; registrar qué se eligió |
| El instalador borra o monta el SSD de 1 TB | Kubuntu desaparece del menú de arranque | Desconectar físicamente el de 1 TB durante la instalación; verificar `lsblk` antes de continuar |
| El login de Claude Code falla sin navegador | `claude` se queda esperando | Hacer el login por SSH desde el Mac con la URL que imprime; si no, usar `ANTHROPIC_API_KEY` temporal y volver a Max después |
| El driver NVIDIA se rompe con un kernel nuevo | `nvidia-smi` falla tras `apt upgrade` | `apt-mark hold` del driver; paquete DKMS; `unattended-upgrades` sin reinicios |
| Modo híbrido: el kernel pagina los expertos a disco | tg cae a < 5 tok/s | `--mlock`, verificar `free -g` antes de arrancar, nada más corriendo en el PC |
| El PC se apaga o se duerme y los hooks quedan colgados | Claude Code espera 60 s por hook | Timeouts cortos en hooks (10 s), `LOCAL_LLM_DISABLED=1`, Wake-on-LAN |
| Calidad insuficiente para una tarea | Reportes del A/B o de la Fase 7 con mayoría de "no" | Esa tarea vuelve a un modelo de pago; no se fuerza el local |
| Consumo eléctrico 24/7 (~50–70 kWh/mes) | Factura | Límite de potencia (`nvidia-smi -pl`), apagar de día si solo se usa el nocturno, Wake-on-LAN |
| El ahorro no justifica el mantenimiento | Pocas llamadas en un mes | Revisar uso a los 30 días; si es bajo, dejar solo los hooks |
