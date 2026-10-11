# Estado SDD

<!-- Puntero de reanudación. Claude lo actualiza en CADA transición (inicio/fin de tarea, cambio de fase, decisión, bloqueo).
     Editar este archivo = checkpoint (lo registra el hook). Mantenlo corto: el detalle va en specs/ y journal.md.
     fase: constitution | specify | clarify | plan | tasks | implement | verify | done
     estado_tarea: - | en_progreso | hecha | bloqueada -->

feature_activa: 002-migracion-aws
fase: clarify
tarea_actual: -
estado_tarea: -

## Siguiente paso

Ejecutar `/sdd-clarify` sobre specs/002-migracion-aws/spec.md: resolver las 3 dudas (qué hace el workflow manual — HU-2/RF-013; importar vs referenciar recursos creados a mano — RF-010; quién aplica el esquema — RF-016). Después, el usuario aprueba la spec para `/sdd-plan`.

## Contexto de trabajo

<!-- Lo que se perdería si la sesión se corta y no está en otros archivos:
     hipótesis en curso, comandos útiles, gotchas, archivos a mirar, lo que ibas a probar. -->

- Rama `aws-provisioning`. Numeración 002 porque `docs/` ya contiene la spec 001-servicio-geoespacial original.

## Bloqueos / preguntas abiertas

- 3 `[NEEDS CLARIFICATION]` en la spec 002 (ver siguiente paso).
