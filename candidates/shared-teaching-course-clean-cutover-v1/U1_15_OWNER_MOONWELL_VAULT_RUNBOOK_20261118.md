# Titus U1.15 — Moonwell owner vault and synthetic recovery runbook

**HELD; NO real data access or backup.** Neither vault, key nor recovery medium was created by GitHub. Owner runs these steps locally.

## Required independent custody

- Primary owner-controlled vault on Moonwell, *only encrypted capsules and separately encrypted witnesses*. An encrypted internal disk alone is insufficient.
- Separately mounted, encrypted external backup volume holding sealed replicas, never plaintext.
- Different encrypted and independently recoverable offline key medium, held separately from both primary and backup. Private key never enters Git, synced folders, chat, issues, logs or CI.
- Recipient public X.509 certificate corresponding to a private 0600 RSA key on that key medium. Public certificate itself is not secret.
- Owner's separate actual restore/recovery evidence after the local fictional drill. Do not mistake different filesystem IDs for proof of geographically independent storage or real disaster recovery.

## Owner-only setup on Moonwell

1. Use Terminal as your signed-in account, not as root. Check main disk encryption with: fdesetup status. If FileVault is disabled, stop before any real backup.
2. Confirm which implementation is active: openssl version. U1.12 uses authenticated CMS AES-256-GCM, previously tested with OpenSSL. Prefer a trusted installed OpenSSL 3.x executable; some macOS defaults expose LibreSSL instead. Do NOT silently change the encryption algorithm or route to a new provider. If the intended OpenSSL 3 binary is absent, set it up deliberately before the owner-run drill.
3. Set restrictive defaults: umask 077. Create a private primary vault *outside Git, Dropbox and other synced folders*:

    mkdir -p "$HOME/Private"
    chmod 700 "$HOME/Private"
    mkdir -m 700 "$HOME/Private/TitusHistoricalVault"

   If this directory already exists, inspect its contents and ownership rather than overwriting.
4. Mount two separate encrypted physical volumes: one to hold encrypted replica files and one holding the owner-managed decryption key. Create dedicated folders owned by your user, 0700. The U1.15 real-mode drill demands distinct mounted filesystems for vault, replica and key file.
5. Create a long-lived public X.509 recipient certificate and corresponding 0600 RSA private key directly on your separately encrypted **key** volume, while mounted. U1.12's current verifier reads a PEM private key without prompting for an interactive passphrase, so **do not put this otherwise-unencrypted key file on an unencrypted or cloud-synced drive**. Owner must physically retain an independently recoverable key copy. This runbook deliberately does not generate or transport keys on your behalf.
   When you have positively verified that the dedicated key volume is encrypted, this is an example of locally generating an X.509 certificate/key pair **directly on that mounted encrypted medium** (replace the placeholder; never run against an unencrypted or synced path):

       KEYDIR="/Volumes/YOUR_ENCRYPTED_KEY_VOLUME/keys"
       umask 077
       test -d "/Volumes/YOUR_ENCRYPTED_KEY_VOLUME" || exit 1
       mkdir -m 700 "$KEYDIR"
       test ! -e "$KEYDIR/titus-owner-private.pem" || exit 1
       test ! -e "$KEYDIR/titus-owner-cert.pem" || exit 1
       openssl req -x509 -newkey rsa:3072 -noenc -days 365 \
         -keyout "$KEYDIR/titus-owner-private.pem" \
         -out "$KEYDIR/titus-owner-cert.pem" \
         -subj "/CN=Titus historical archive owner"
       chmod 600 "$KEYDIR/titus-owner-private.pem"
       openssl x509 -in "$KEYDIR/titus-owner-cert.pem" -noout -checkend 604800

   The -noenc option leaves the PEM private key itself unencrypted; the **volume's verified encryption and physical isolation are mandatory**. Create a separate recovery copy of this key only on another independently encrypted/offline medium using an owner-controlled procedure, and prove it can be read later. The owner should preserve a durable copy of the **public** certificate separately so future backup sealing does not require leaving the offline key medium attached. Never paste key contents into a tool or chat.

6. Check out the exact U1.15 held Noel source on Moonwell. With all three owner-selected locations prepared, run this **fictional-only** command (substitute actual external volume names):

    python3 scripts/titus-u115-local-owner-vault-drill.py \
      --vault-dir "$HOME/Private/TitusHistoricalVault" \
      --replica-dir "/Volumes/YOUR_ENCRYPTED_BACKUP_VOLUME/TitusSealedCopies" \
      --recipient-certificate "/Volumes/YOUR_ENCRYPTED_KEY_VOLUME/keys/titus-owner-cert.pem" \
      --private-key "/Volumes/YOUR_ENCRYPTED_KEY_VOLUME/keys/titus-owner-private.pem"

7. Accept only: PASS fictional sealed-copy and key verification only; no real backup or independent disaster recovery certified.

The script validates existing directory ownership/private permissions, X.509 remaining validity, different mounted filesystems, exclusive synthetic artifact creation, independently verified authentic encrypted archive and witness in both locations, exact encrypted replica bytes and removal of its own synthetic artifacts. It never selects a database row or ingests non-fictional data.

The separate, real owner-offline-disaster-recovery drill must prove key custody, decryptability and independently restorable historical database materials after loss of the primary device; this fictional test alone is not that proof.

## Remaining historical backup gates

- Reviewed precise row selection and FK closure for the 45 relation expanded historical scope, including 15 Course shells, Program/Formation records and six protected original customer-history tables, with no shared-source overcapture.
- New separately scoped owner approval for a protected consistent customer-data read.
- Real encrypted PostgreSQL archival and independently restored PG17 equality checks for original IDs, author links, source grants, timestamps, text bytes, revisions and dependencies.
- Independently approved canonical Course cutover and deletion via RESTRICT only after no-loss proof. Never interpret catalog CASCADE metadata as permission to delete.

**No customer data, user keys, primary storage, production schemas, migration, release, or deployment is created by the U1.15 branch or its CI.**
