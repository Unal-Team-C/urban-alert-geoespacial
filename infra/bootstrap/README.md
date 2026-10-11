# Recursos de arranque (se crean a mano una sola vez)

Terraform no gestiona estos recursos: los necesita para poder ejecutarse, y el workflow de desaprovisionamiento no debe borrarlos (spec 002, RF-010c). Están listados también en [../INVENTARIO.md](../INVENTARIO.md).

Cuenta `348364742283`, región `us-east-2`. Los JSON de esta carpeta son la copia versionada de lo que hay configurado en AWS: si se cambia una política en la consola, hay que actualizar aquí el JSON (y al revés).

## 1. Proveedor OIDC de GitHub

IAM → Identity providers → Add provider:

- Tipo: OpenID Connect
- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

```bash
aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com
```

## 2. Rol que asumen los workflows

- Relación de confianza: [github-oidc-trust.json](github-oidc-trust.json). Admite todos los repos de `Unal-Team-C`, solo desde la rama `main`. Los repos de la organización usan el *subject* inmutable de GitHub, con IDs: `repo:Unal-Team-C@335834608/<repo>@<id>:ref:refs/heads/main` (se ve con `gh api repos/Unal-Team-C/<repo>/actions/oidc/customization/sub`). Por eso el patrón incluye `@335834608` (ID de la organización, no cambia aunque se renombre); el segundo patrón cubre repos con el formato clásico. Los workflows no usan *environments* de GitHub: un *environment* cambiaría el `sub` del token a `repo:<org>/<repo>:environment:<nombre>` y la confianza dejaría de cumplirse.
- Políticas gestionadas adjuntas:
  - `github-actions-urban-alertPolicy` → [github-deploy-policy.json](github-deploy-policy.json): ECR, ECS Express, `iam:PassRole` sobre `role/urban-alert-*`, RDS, S3, SQS, WAF, red y secretos.
  - `github-actions-urban-alert-terraform` → [github-terraform-policy.json](github-terraform-policy.json): lo que Terraform necesita además para importar, gestionar y destruir (ECR, roles `urban-alert-*`, logs, secretos de RDS, tarea del esquema).
- El nombre del rol empieza por `github-actions-`, no por `urban-alert-`: así los permisos de IAM de Terraform no le alcanzan y el pipeline no puede modificarse a sí mismo.

## 3. Bucket del estado de Terraform

`urban-alert-tfstate-348364742283` (us-east-2):

- Object Ownership: ACLs deshabilitadas (bucket owner enforced).
- Block Public Access: las cuatro opciones activadas.
- Versionado activado.
- Cifrado por defecto SSE-S3.
- Política: [tfstate-bucket-policy.json](tfstate-bucket-policy.json) (rechaza conexiones sin TLS).
- Ciclo de vida: [tfstate-lifecycle.json](tfstate-lifecycle.json) (borra versiones no actuales de más de 90 días, conservando las 10 más recientes).

```bash
B=urban-alert-tfstate-348364742283
aws s3api create-bucket --bucket $B --region us-east-2 --create-bucket-configuration LocationConstraint=us-east-2
aws s3api put-public-access-block --bucket $B --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --bucket $B --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket $B --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
aws s3api put-bucket-policy --bucket $B --policy file://tfstate-bucket-policy.json
aws s3api put-bucket-lifecycle-configuration --bucket $B --lifecycle-configuration file://tfstate-lifecycle.json
```

Cada servicio usa su propia clave dentro del bucket (`geoespacial/base.tfstate`, `geoespacial/service.tfstate`). El bloqueo usa objetos `.tflock` (`use_lockfile`), sin DynamoDB.

## 4. Secretos y variables de GitHub

Settings → Secrets and variables → Actions:

| Tipo | Nombre | Valor |
|---|---|---|
| Secreto | `AWS_ROLE_ARN` | ARN del rol del paso 2 |
| Variable | `AWS_REGION` | `us-east-2` |

El resto de la configuración (nombres, tamaños, bucket del estado) está en el código de `infra/`.
