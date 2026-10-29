# Babymama 🇰🇪

Marketplace de vêtements de seconde main (friperie / *mitumba*) pour Nairobi, inspirée de Vinted.
Un seul code Flutter pour le **web, Android et iOS**, un backend Node.js, une app **livreur** et un **back-office admin**.
Toutes les interfaces sont en **anglais et en français**.

```
babymama/
├── backend/                 API REST - Node.js 20, TypeScript, Express, Prisma, PostgreSQL
├── packages/babymama_core/  Code Flutter partagé : client API, modèles, session, traductions EN/FR, thème, carrousel
├── apps/customer_app/       App client  (web + Android + iOS)
├── apps/driver_app/         App livreur (Android + iOS)
├── apps/admin_app/          Back-office (Flutter web)
├── scripts/                 setup_flutter.sh, check_i18n.sh
└── docker-compose.yml       PostgreSQL + API
```

## Fonctionnalités

| Domaine | Ce qui est fait |
|---|---|
| Comptes | Inscription e-mail / mot de passe, **connexion Google** (web, Android, iOS), profil, adresses enregistrées, rôles `CUSTOMER`, `DRIVER`, `SUPPORT`, `ADMIN` |
| Boutique | Babymama est le seul vendeur. Site web avec en-tête (recherche à suggestions instantanées, rayons **Femmes \| Hommes \| Enfants** avec menu au survol), contenu centré sur 1200 px, pied de page ; mise en page téléphone sur mobile. **Carrousel** à flèches (pubs, promos, catégories, lots + nouveautés), catalogue avec filtres (sous-catégorie, tailles, couleurs, état, prix, tri), fiche produit (galerie à flèches, fil d'Ariane), 2ᵉ photo au survol des cartes, favoris |
| Catégories et tailles | Chaque catégorie a une échelle de tailles, héritée de son rayon si elle n'en définit pas : **vêtements** XS à 3XL, **enfants** par âge (0-3 mois à 14 ans), **chaussures** pointure EU 16 à 46, **accessoires** sans taille. L'admin choisit la taille dans cette liste et le serveur refuse une taille hors échelle. Couleur choisie dans une liste de 14 couleurs traduites |
| Ventes groupées | **Lots** (plusieurs articles vendus ensemble à prix réduit) **et remise multi-achat** par paliers (ex. 2 articles -5 %, 3 articles -10 %, 5 articles -15 %), configurables dans l'admin |
| Commande | Panier, devis côté serveur (prix + stock + remise), zones de livraison de Nairobi avec frais, code de livraison à 4 chiffres |
| Paiements | **M-Pesa (STK Push Daraja)**, **Airtel Money**, **carte via Flutterwave**, paiement à la livraison. Architecture à fournisseurs : on ajoute un moyen de paiement en implémentant une interface. Mode simulation en développement |
| Stock | Stock par produit, **réservation atomique** à la commande (deux clients ne peuvent pas acheter la dernière pièce), libération automatique des commandes non payées après 15 min, **journal de tous les mouvements**, alertes stock faible, réassort / correction / retour client, valeur du stock |
| WooCommerce | Import complet, **webhooks** (produit créé / modifié / supprimé → app), renvoi du stock vers WooCommerce, option d'envoi des nouveaux produits et des commandes payées |
| Livraison | App livreur : en ligne / hors ligne, livraisons disponibles / en cours / historique, accepter → récupéré → en route → livré (code client), signalement d'échec, appel / SMS / itinéraire Google Maps, **position GPS envoyée toutes les 30 s**, espèces encaissées |
| Support | Le client écrit au support (lié ou non à une commande), conversation type chat, raccourcis WhatsApp / appel ; l'équipe répond depuis l'admin |
| Avis | Le client **note sa commande** (1-5 étoiles + commentaire) **et le livreur** après livraison |
| Admin | Tableau de bord (CA, commandes, livraisons à attribuer, remboursements), produits, stock, commandes (workflow, attribution livreur), livreurs et équipe, carrousel, lots, paliers, support, clients, avis, zones, WooCommerce |

## 1. Démarrer le backend

Prérequis : Node.js 20+, PostgreSQL 14+ (ou Docker).

```bash
cd backend
cp .env.example .env
npm install
npx prisma migrate deploy
npm run db:seed
npm run dev
```

L'API écoute sur `http://localhost:4000` (`GET /health` pour vérifier). Le seed crée :

| Rôle | E-mail | Mot de passe |
|---|---|---|
| Admin | admin@babymama.co.ke | ChangeMe123! (variable `SEED_ADMIN_PASSWORD`) |
| Support | support@babymama.co.ke | Support123! |
| Livreur | rider@babymama.co.ke | Rider123! |
| Client | customer@babymama.co.ke | Customer123! |

ainsi que 18 zones de Nairobi, les rayons Femmes / Hommes / Enfants et leurs sous-catégories, 21 articles de démo, 3 diapositives de carrousel, un lot et les paliers de remise. **Changez ces mots de passe avant toute mise en ligne.**

Avec Docker (base + API) :

```bash
cp backend/.env.example backend/.env
docker compose up -d --build
docker compose exec api npx tsx prisma/seed.ts
```

Tests :

- `npm test` : tests unitaires du calcul des remises ;
- `npm run e2e` : test de bout en bout (98 vérifications) contre l'API lancée et la base seedée. Il couvre inscription, catalogue, devis, commande, paiement simulé et callback M-Pesa, expiration des commandes non payées, achat simultané de la dernière pièce, lots, workflow admin, app livreur (code de livraison, espèces), avis, support, stock, annonces clients, carrousel, zones et upload d'images. Il crée des données de test et remet en stock les articles de démo (`BM-DEMO-*`) : à lancer sur une base de développement. Les routes de connexion bloquent une adresse IP après 20 échecs en 15 min (les connexions réussies ne comptent pas).

Après une modification de `prisma/schema.prisma` : `npx prisma migrate dev --name <description>`.

## 2. Lancer les apps Flutter

Prérequis : Flutter 3.35+ (Dart 3.9+), testé avec Flutter 3.47.8. Une seule fois, générer les dossiers natifs et les permissions :

```bash
bash scripts/setup_flutter.sh
```

Puis :

```bash
# App client sur le web
cd apps/customer_app
flutter run -d chrome --dart-define=API_URL=http://localhost:4000

# App client sur un émulateur Android (10.0.2.2 = votre PC vu depuis l'émulateur)
flutter run --dart-define=API_URL=http://10.0.2.2:4000

# App livreur
cd apps/driver_app
flutter run --dart-define=API_URL=http://10.0.2.2:4000

# Back-office
cd apps/admin_app
flutter run -d chrome --dart-define=API_URL=http://localhost:4000
```

Sur un vrai téléphone, utilisez l'IP de votre PC sur le réseau local (ex. `http://192.168.1.20:4000`).

Builds de production :

```bash
flutter build web --release --dart-define=API_URL=https://api.babymama.co.ke   # customer_app et admin_app
flutter build appbundle --release --dart-define=API_URL=https://api.babymama.co.ke
flutter build ipa --release --dart-define=API_URL=https://api.babymama.co.ke   # sur macOS
```

## 3. Connexion Google

1. Dans Google Cloud Console > *APIs & Services > Credentials*, créez des identifiants OAuth :
   - un client **Web** (origines autorisées : vos URL web, ex. `http://localhost:5000`, `https://babymama.co.ke`) ;
   - un client **Android** (package `ke.babymama.babymama` + empreinte SHA-1 de votre keystore) ;
   - un client **iOS** (bundle ID `ke.babymama.babymama`).
2. Backend : `GOOGLE_CLIENT_IDS=<web_client_id>,<ios_client_id>`.
3. Apps : ajoutez `--dart-define=GOOGLE_WEB_CLIENT_ID=<web_client_id>` (et `--dart-define=GOOGLE_IOS_CLIENT_ID=<ios_client_id>` pour iOS).
4. iOS : dans `apps/customer_app/ios/Runner/Info.plist`, ajoutez le *reversed client ID* dans `CFBundleURLTypes` (voir la doc du package `google_sign_in`).
5. Web : lancez avec un port fixe déclaré dans la console Google, ex. `flutter run -d chrome --web-port 5000`.

## 4. Paiements mobiles

Le backend expose `GET /api/payments/methods` (moyens actifs) et `POST /api/payments/orders/:orderId` (démarre le paiement). L'app interroge ensuite `GET /api/payments/:id` jusqu'à confirmation.

| Moyen | Variables | URL de callback à déclarer |
|---|---|---|
| M-Pesa (Daraja STK Push) | `MPESA_CONSUMER_KEY`, `MPESA_CONSUMER_SECRET`, `MPESA_SHORTCODE`, `MPESA_PASSKEY`, `MPESA_ENV`, `MPESA_TRANSACTION_TYPE` (paybill ou till + `MPESA_PARTY_B`) | automatique : `{PUBLIC_URL}/api/payments/callbacks/mpesa/{MPESA_CALLBACK_TOKEN}` |
| Airtel Money | `AIRTEL_CLIENT_ID`, `AIRTEL_CLIENT_SECRET`, `AIRTEL_ENV` | `{PUBLIC_URL}/api/payments/callbacks/airtel/{AIRTEL_CALLBACK_TOKEN}` dans le portail Airtel |
| Carte (Flutterwave) | `FLUTTERWAVE_SECRET_KEY`, `FLUTTERWAVE_WEBHOOK_HASH`, `FLUTTERWAVE_REDIRECT_URL` | `{PUBLIC_URL}/api/payments/callbacks/flutterwave` dans le dashboard Flutterwave |
| Paiement à la livraison | `CASH_ON_DELIVERY=true` | - le livreur encaisse et confirme avec le code client |

- `PUBLIC_URL` doit être en **HTTPS public** pour recevoir les callbacks (en local : ngrok ou Cloudflare Tunnel).
- Sans identifiants et avec `PAYMENTS_MOCK=true`, les paiements sont **simulés** (validés au bout de 4 s) : pratique pour tester tout le parcours.
- Un montant reçu inférieur au total est refusé ; un paiement arrivé après expiration de la commande la laisse « annulée + payée » et apparaît dans « Remboursements à traiter ».
- Ajouter un fournisseur (Pesapal, T-Kash, Equitel…) : implémenter `PaymentProvider` dans `backend/src/modules/payments/providers/`, l'enregistrer dans `providers/index.ts` et ajouter sa route de callback.

## 5. WooCommerce (optionnel)

1. WooCommerce > Réglages > Avancé > **API REST** : créez une clé en lecture/écriture → `WOO_URL`, `WOO_CONSUMER_KEY`, `WOO_CONSUMER_SECRET`.
2. WooCommerce > Réglages > Avancé > **Webhooks** : créez *Produit créé*, *Produit mis à jour*, *Produit supprimé* et *Produit restauré*, URL `{PUBLIC_URL}/api/woocommerce/webhook`, secret = `WOO_WEBHOOK_SECRET`.
3. Admin Babymama > Paramètres > **Importer tous les produits WooCommerce** pour la première synchronisation.

Les produits ajoutés dans WooCommerce arrivent alors automatiquement dans l'app ; chaque vente, annulation ou ajustement de stock fait dans Babymama est renvoyé à WooCommerce (`WOO_PUSH_STOCK`). Options : `WOO_PUSH_PRODUCTS` (créer dans Woo les produits ajoutés depuis l'admin Babymama) et `WOO_PUSH_ORDERS` (copier les commandes payées). Les attributs Woo `Size/Taille`, `Brand/Marque`, `Color/Couleur`, `Condition/État` sont reconnus.

## 6. Cycle d'une commande

```
Client : panier → devis → commande (stock réservé) ─┬─ M-Pesa / Airtel / carte → payé → CONFIRMED
                                                    └─ paiement à la livraison → CONFIRMED
         non payé après 15 min → CANCELLED, stock libéré automatiquement
Admin  : CONFIRMED → PREPARING → READY, attribue un livreur (ou un livreur en ligne la prend)
Livreur: ACCEPTED → PICKED_UP (commande OUT_FOR_DELIVERY) → IN_TRANSIT → DELIVERED avec le code à 4 chiffres du client
Client : note la commande et le livreur, peut écrire au support à tout moment
```

## 7. API (résumé)

| Préfixe | Accès | Rôle |
|---|---|---|
| `/api/auth` | public / connecté | register, login, google, me, change-password, me/addresses |
| `/api/home`, `/api/products`, `/api/categories`, `/api/bundles`, `/api/zones`, `/api/discount-tiers` | public | catalogue |
| `/api/me/favorites`, `/api/me/listings` | connecté | favoris, articles mis en vente |
| `/api/orders` | connecté | quote, créer, lister, détail, annuler, noter |
| `/api/payments` | connecté + callbacks | méthodes, démarrer, statut, callbacks M-Pesa / Airtel / Flutterwave |
| `/api/support` | connecté | tickets et messages |
| `/api/driver` | livreur | profil, position, livraisons, accepter, statut, terminer, échec |
| `/api/uploads` | connecté | envoi d'images (stockage disque local, à remplacer par S3/Cloudinary en production) |
| `/api/woocommerce/webhook` | signature HMAC | synchro produits |
| `/api/admin/...` | admin (support : `/admin/support` seulement) | stats, produits, stock, commandes, staff, livreurs, utilisateurs, avis, bannières, lots, paliers, zones, catégories, WooCommerce |

Les erreurs de l'API sont traduites selon l'en-tête `Accept-Language` (envoyé automatiquement par les apps).

## 8. Avant la mise en production

- Changer `JWT_SECRET`, les mots de passe du seed et les jetons de callback ; mettre `PAYMENTS_MOCK=false`.
- Héberger l'API derrière HTTPS (Nginx / Caddy), restreindre `CORS_ORIGINS` aux domaines web.
- Remplacer le stockage local des images par S3 / Cloudinary (`backend/src/modules/uploads`).
- Appliquer les migrations versionnées avec `npx prisma migrate deploy` (fait automatiquement par l'image Docker).
- Pistes suivantes : notifications push (Firebase Cloud Messaging) pour les changements de statut, versement M-Pesa B2C automatique aux vendeurs, carte temps réel du livreur dans l'app client.
- Vérifier les traductions après chaque ajout de texte : `bash scripts/check_i18n.sh`.

## 9. Hébergement sur Vercel

Trois projets Vercel, tous sur le plan gratuit Hobby (usage de test, non commercial) :

| Projet | Dossier | Contenu |
|---|---|---|
| API | `backend/` | L'app Express tourne comme une fonction (`api/index.js`, `vercel.json`). `npm run vercel-build` génère Prisma, applique les migrations et compile. |
| Boutique | `apps/customer_app/build/web` | Site client compilé avec `flutter build web --dart-define=API_URL=<url de l'API>` |
| Admin | `apps/admin_app/build/web` | Back-office compilé de la même façon |

Variables de l'API sur Vercel : `DATABASE_URL` (Neon Postgres, ajouté par l'intégration), `BLOB_READ_WRITE_TOKEN` (Vercel Blob, pour les photos), `JWT_SECRET`, `PUBLIC_URL`, `CORS_ORIGINS` (URL de la boutique et de l'admin), `PAYMENTS_MOCK=true` tant que les vrais paiements ne sont pas branchés.

Différences avec un serveur classique : pas de minuteur en continu, donc les commandes non payées sont libérées au fil des requêtes (une fois par minute au plus) ; pas de disque, donc les photos vont sur Vercel Blob.

Remplir la base la première fois, depuis votre poste, avec l'URL Neon :

```bash
cd backend
DATABASE_URL="<url neon>" SEED_ADMIN_PASSWORD="<mot de passe fort>" SEED_DEMO_PASSWORD="<autre mot de passe>" npx prisma migrate deploy
DATABASE_URL="<url neon>" SEED_ADMIN_PASSWORD="<mot de passe fort>" SEED_DEMO_PASSWORD="<autre mot de passe>" npm run db:seed
```
