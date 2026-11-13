# php-devops-tp — Pipeline CI/CD DevSecOps

TP03 SI5 DevSecOps (Polytech Nice Sophia) — Omar AIT LHOUSS · Saad BENAQA · Arous MOHAMED · Ahmed TAMANI

Application PHP qui génère une image PNG (GD + Carbon). Si la variable `APP_SECRET` est définie, sa valeur est affichée : cela sert à prouver que le secret est bien injecté par Infisical en production.

- Production : http://35.180.247.99
- Image : `ghcr.io/omaral20/php-devops-tp` (privée)

## Pipeline (`.circleci/config.yml`)

```
git push ─► build-setup ─► [lint-phpcs, lint-phpmd, lint-php-doc-check, metrics-phpmetrics,
                            metrics-phploc, security-check-dependencies*, test-phpunit*]   (* bloquants)
                │
                ▼ (tests + audit + phpcs OK)
        build-docker-image ─► security-trivy-image ─► hold (approbation) ─► deploy-ssh-production (main)
                │ push GHCR                                                  └► deploy-ssh-staging (release/*)
```

| Job | Rôle |
| --- | --- |
| `debug-info` | Environnement d'exécution (sans les variables secrètes) |
| `build-setup` | `composer install`, cache sur `composer.lock`, workspace partagé |
| `lint-phpcs` | PSR-12 + PHPCompatibility (PHP 8.2+) — rapport checkstyle |
| `lint-phpmd` | PHP Mess Detector — rapport HTML (non bloquant) |
| `lint-php-doc-check` | Fonctions complexes non documentées (non bloquant) |
| `metrics-phpmetrics` | Rapport HTML de métriques (non bloquant) |
| `metrics-phploc` | Taille du code, texte + JSON (non bloquant) |
| `security-check-dependencies` | `composer audit --no-dev` — **bloquant** |
| `test-phpunit` | Suite `Unit`, résultats JUnit — **bloquant** |
| `build-docker-image` | Build + push GHCR, tag `<branche>-<sha7>` |
| `security-trivy-image` | Scan Trivy HIGH/CRITICAL de l'image publiée |
| `hold` | Approbation manuelle (main, master, release/*) |
| `deploy-ssh-production` | Déploiement de l'image sur l'EC2 (main, master) |
| `deploy-ssh-staging` | Idem en staging, port 8080 (release/*) |

Les outils d'analyse sont installés avec `composer global require` pour ne pas modifier `composer.json`. Les rapports sont dans l'onglet **Artifacts** de chaque job.

## Variables CircleCI (Project Settings → Environment Variables)

| Variable | Contenu |
| --- | --- |
| `GHCR_USERNAME` | Compte GitHub propriétaire de l'image |
| `GHCR_PAT` | Token GitHub `write:packages` (push depuis la CI) |
| `GHCR_READ_PAT` | Token GitHub `read:packages` uniquement (pull sur l'EC2) |
| `PRODUCTION_SSH_USER` / `PRODUCTION_SSH_HOST` | Utilisateur et IP de l'EC2 |
| `PRODUCTION_SSH_KEY_B64` | Clé privée de déploiement encodée en base64 |
| `PRODUCTION_KNOWN_HOSTS` | (optionnel) clé publique du serveur ; les clés sont aussi versionnées dans `.circleci/known_hosts` |
| `STAGING_*` | Mêmes variables pour le staging |

## Déploiement

`deploy-ssh-production` charge la clé de déploiement, vérifie l'identité du serveur (`StrictHostKeyChecking=yes`), connecte Docker à GHCR avec le token en lecture seule, puis exécute `scripts/deploy.sh` sur l'EC2 :

1. `docker pull` de l'image du commit ;
2. obtention d'un jeton Infisical (Machine Identity, Universal Auth) à partir de `/etc/php-devops/prod.env` (droits 600) ;
3. remplacement du conteneur (`--restart unless-stopped`, `no-new-privileges`, 256 Mo, 0,5 CPU), lancé avec `infisical run --env=prod -- apache2-foreground` ;
4. vérification que l'application répond sur le port 80, sinon affichage des logs et échec du job.

### Préparer un serveur

```bash
sudo apt update && sudo apt install -y docker.io curl
sudo usermod -aG docker ubuntu
sudo mkdir -p /etc/php-devops
# /etc/php-devops/prod.env (chmod 600) :
# INFISICAL_CLIENT_ID=...
# INFISICAL_CLIENT_SECRET=...
# INFISICAL_PROJECT_ID=<UUID du projet>
# INFISICAL_API_URL=https://eu.infisical.com/api
```

## Lancer en local

```bash
docker build -f Docker/Dockerfile -t php-devops:local .
docker run --rm -p 8080:80 php-devops:local   # http://localhost:8080
```

## Sécurité (résumé)

- Aucun secret dans le dépôt ni dans l'image ; secrets CircleCI masqués ; `APP_SECRET` uniquement dans Infisical.
- Moindre privilège : token GHCR en lecture seule sur le serveur, identité Infisical `Viewer` sur un seul projet.
- Image sans Xdebug, sans `phpinfo()`, sans dépendances de dev, code non modifiable par Apache, `HEALTHCHECK`.
- Vérification de l'hôte SSH, approbation manuelle avant la production, audit des dépendances bloquant, scan Trivy.
