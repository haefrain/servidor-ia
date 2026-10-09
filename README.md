# servidor-ia

Servidor de inferencia local (llama.cpp + CUDA) en un PC con i5-12600K, RTX 3070 Ti 8 GB y 32 GB DDR4, corriendo Ubuntu Server 24.04. Expone una API OpenAI-compatible por Tailscale para que la orquesta de agentes de VantLabs delegue tareas repetitivas a un modelo gratuito.

- `SPEC.md` — el plan completo por fases, con criterios de aceptación. Lo ejecuta Claude Code.
- `CLAUDE.md` — reglas para Claude Code y tabla de estado de las fases.
- `bootstrap.sh` — deja un Ubuntu Server recién instalado listo para arrancar Claude Code.
- `config/` — unidades systemd y `.env` de cada modelo (sin secretos), versionados conforme se crean.
- `reports/` — reportes de cada fase y benchmarks.

## Instalación desde cero

**1. Ubuntu Server (a mano, ~15 min)**

- Descarga Ubuntu Server 26.04 LTS (o 24.04) y graba un USB.
- Desconecta físicamente el SSD de 1 TB (tiene el Kubuntu de respaldo).
- Instala en el SSD de 512 GB: LVM por defecto, sin cifrado, usuario `efra`, marca **Install OpenSSH server**, sin snaps extra.
- Vuelve a conectar el de 1 TB; en BIOS deja el de 512 como primer arranque.

**2. Bootstrap (un comando)**

```bash
git clone https://github.com/haefrain/servidor-ia d && bash d/bootstrap.sh
```

Instala actualizaciones, Tailscale, Claude Code y clona este repo en `~/dev/servidor-ia`. Es idempotente.

**3. Login y arranque de Claude Code**

```bash
sudo tailscale up            # si no quedó conectado
# desde el Mac:
ssh efra@<ip-tailscale>
cd ~/dev/servidor-ia && claude
```

Claude Code imprime una URL: ábrela en el Mac, inicia sesión con la cuenta Max y pega el código. Luego:

> Lee CLAUDE.md y SPEC.md. Ejecuta la Parte B de la Fase 1. Detente al final de cada fase y reporta.

## Modos de operación

| Modo | Modelo | Comando |
| --- | --- | --- |
| Diurno (por defecto) | Qwen3.5-9B, 4 slots | `sudo /opt/llm/bin/switch-model.sh qwen` |
| Diurno alterno | Granite 4.1-8B | `sudo /opt/llm/bin/switch-model.sh granite` |
| Por lotes / nocturno | Qwen3.6-35B-A3B (expertos en RAM) | `sudo /opt/llm/bin/switch-model.sh hibrido` |

Desde el Mac, con los alias de la Fase 4: `llm-switch <modo>`, `llm-wake`.
