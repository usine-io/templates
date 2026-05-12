# Bienvenue sur Spark

> Tu fais partie d'une equipe qui utilise Spark. Cette page t'explique ce que c'est, ce que tu peux en faire, et comment demander de nouvelles choses.

---

## Spark, c'est quoi ?

Spark est un petit serveur pose dans ton entreprise (un Mac Mini). Il connecte tes logiciels existants entre eux — ton CRM, ta facturation, tes fichiers Excel, tes outils de gestion — sans les remplacer.

Concretement, Spark te donne :

- **Des tableaux de bord** pour voir des donnees qui n'etaient nulle part (ou dans la tete de quelqu'un)
- **Des formulaires** pour saisir des informations sans devoir ouvrir 3 logiciels differents
- **Des automatisations** : quand un evenement arrive dans un logiciel, quelque chose se passe dans un autre

Tout reste dans l'entreprise. Pas de cloud obscur, pas d'abonnement par utilisateur.

---

## Ce que tu utilises au quotidien

### Les ecrans metier (`<prefix>-app.<domain>`)

C'est ton adresse principale. Tu y trouves :

- Les **formulaires de saisie** crees pour ton equipe
- Les **tableaux de bord** avec les indicateurs qui comptent
- Les **vues** filtrees sur les donnees qui te concernent

Tu n'as pas besoin de mot de passe specifique — l'acces est gere par le tunnel securise de l'entreprise.

### NocoDB (`<prefix>-db.<domain>`)

C'est la base de donnees visuelle. Ca ressemble a un tableur, mais en plus puissant :

- Tu peux **filtrer, trier, grouper** les donnees
- Tu peux creer tes propres **vues** (par equipe, par statut, par date...)
- Tu peux utiliser les **formulaires natifs** pour de la saisie simple

Si tu connais Airtable ou Notion, c'est le meme principe — mais heberge chez toi.

### Ce que tu ne touches pas

- **n8n** (`<prefix>-n8n.<domain>`) — c'est le moteur d'automatisation. Seul l'admin Spark y accede pour configurer les connexions entre logiciels.
- **Les fichiers `.env`** ou la configuration serveur — c'est l'infra, pas ton probleme.

---

## Demander un nouvel outil

Tu as un besoin ? Un truc que tu fais a la main et qui pourrait etre automatise ? Un tableau de bord qui te manque ?

**Pas besoin de spec technique.** Decris ton besoin en langage normal :

> *"J'aimerais un ecran ou je vois toutes les commandes en retard, avec le nom du fournisseur et la date prevue. Et pouvoir cocher 'recu' directement."*

> *"Quand on cree un devis dans Pennylane, j'aimerais que ca cree automatiquement une ligne dans notre suivi de prospection."*

> *"On a un fichier Excel avec les references produits qu'on met a jour chaque lundi. Ce serait bien que ce soit visible dans un tableau partage sans devoir envoyer le fichier par email."*

L'admin Spark (ou Claude Code) transforme ca en prototype fonctionnel. Le cycle est rapide : on construit un premier truc en quelques heures, tu testes, tu dis ce qui manque, on ajuste.

---

## Les regles du jeu

### Tes donnees restent tes donnees

- Tout est stocke sur le Mac Mini dans l'entreprise
- Les mots de passe des logiciels connectes sont chiffres dans un coffre-fort (pas dans des fichiers texte)
- Rien ne sort vers un cloud exterieur sans decision explicite

### Spark ne remplace rien

- Ton CRM reste ton CRM. Ton ERP reste ton ERP
- Spark lit et ecrit dans tes logiciels existants, il ne les remplace pas
- Si tu debranches Spark, tes logiciels continuent de fonctionner exactement comme avant

### Le prototype d'abord

- On construit un premier truc simple, on voit si ca marche, on ameliore
- Pas de projet a 6 mois — des iterations courtes
- Si un prototype ne sert a rien, on le supprime sans consequences

---

## Quelque chose ne marche pas ?

| Symptome | Quoi faire |
|----------|-----------|
| Une page ne charge pas | Verifier que le Mac Mini est allume et connecte au reseau |
| Un formulaire renvoie une erreur | Prevenir l'admin Spark — c'est probablement un workflow a corriger |
| Les donnees ne sont pas a jour | Les synchronisations tournent a intervalles — attendre quelques minutes, puis prevenir l'admin |
| Tu ne trouves plus un ecran | L'adresse est `https://<prefix>-app.<domain>/apps/` — mettre en favori |

Pour tout le reste : parler a l'admin Spark ou ouvrir une discussion sur le canal dedie.

---

*Guide utilisateur Spark v1.0 — ce document evolue avec les retours de l'equipe.*
