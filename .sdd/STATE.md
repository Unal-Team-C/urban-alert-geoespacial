# Estado SDD

<!-- Puntero de reanudación. Claude lo actualiza en CADA transición (inicio/fin de tarea, cambio de fase, decisión, bloqueo).
     Editar este archivo = checkpoint (lo registra el hook). Mantenlo corto: el detalle va en specs/ y journal.md.
     fase: constitution | specify | clarify | plan | tasks | implement | verify | done
     estado_tarea: - | en_progreso | hecha | bloqueada -->

feature_activa: ninguna
fase: constitution
tarea_actual: -
estado_tarea: -

## Siguiente paso

Crear la feature de migración a AWS con `/sdd-new` (CI/CD con GitHub Actions + despliegue en ECS Express Mode + BD PostGIS en RDS). Antes, el usuario crea en GitHub los secretos/variables acordados.

## Contexto de trabajo

<!-- Lo que se perdería si la sesión se corta y no está en otros archivos:
     hipótesis en curso, comandos útiles, gotchas, archivos a mirar, lo que ibas a probar. -->

- Código del servicio copiado desde UrbanAlert `backend/UrbanAlert.Geoespacial` (commit origen 46daa1f). Remoto: https://github.com/Unal-Team-C/urban-alert-geoespacial (privado).
- Los hooks del arnés llaman a `powershell`, que no está instalado en este Mac (macOS): no se ejecutan hasta instalar `pwsh` y ajustar `.claude/settings.json`.

## Bloqueos / preguntas abiertas

- ninguno
