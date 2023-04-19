# Makefile-PKI
This project uses openssl in a makefile to perform certificate authority
operations. Most of the code is taken from Jamie Nguyen's [blog
post](https://jamielinux.com/docs/openssl-certificate-authority/index.html).

## Prerequisites
- [make](https://www.gnu.org/software/make/)
- [openssl](https://www.openssl.org/)
- [envsubst](https://linux.die.net/man/1/envsubst)

## Example Usage

get help
```bash
make help
```

create myca.com root certificate
```bash
CA=myca make ca
```

use ca to sign ica cert for dotrustitco.com
```bash
CA=myca ICA=dotrustitco make ica
```

use ica to sign server cert for example.com
```bash
CA=myca ICA=dotrustitco SERVER=example.com make server
```

setting a NAMESPACE environment variable (default `NAMESPACE=sandbox`)
builds all files under a common output directory
```bash
dest
└── sandbox
    ├── dotrustitco
    │   ├── certs
    │   │   └── 1000.pem
    │   ├── crlnumber
    │   ├── ica-chain.cert.pem
    │   ├── ica.cert.pem
    │   ├── ica.cnf
    │   ├── ica.csr.pem
    │   ├── index.txt
    │   ├── index.txt.attr
    │   ├── index.txt.old
    │   ├── private
    │   │   └── ica.key.pem
    │   ├── serial
    │   └── serial.old
    ├── example.com
    │   ├── private
    │   │   └── server.key.pem
    │   ├── server.cert.pem
    │   ├── server.cnf
    │   └── server.csr.pem
    └── myca
        ├── ca.cert.pem
        ├── ca.cnf
        ├── certs
        │   └── 1000.pem
        ├── crlnumber
        ├── index.txt
        ├── index.txt.attr
        ├── index.txt.old
        ├── private
        │   └── ca.key.pem
        ├── serial
        └── serial.old

9 directories, 26 files
```

## How secure is it?
This project is less secure than Jaime Nguyen's original blog post examples
since it passes plaintext passwords via command-line flags for ease of use.

Please follow [best
practices](https://cheatsheetseries.owasp.org/cheatsheets/Key_Management_Cheat_Sheet.html)
before attempting to use pki in production.

## Make Commands:
- `make help`: Show this help.
- `make clean`: recursively remove all files from the destination namespace.
- `make ca`: generate files for a ca: openssl db files, private keys, config file, etd...
- `make ica`: use ca to sign ica cert and generates its files
- `make server`: use ica to sign server cert and generate private key
- `make usr`: use ica to sign user cert and generate private key
- `make revoke_server`: revoke a server cert
- `make ica_crl`: generate a new CRL list. revocations don't show up in the CRL until it is manually rerun
- `make verify_server`: use openssl to validate the server cert was correctly signed without checking revocation status
- `make dump_server`: use openssl to print a text representation of the server cert
- `make dump_ica_crl`: use openssl to print a text representation of the current crl
- `make serve_ica_ocsp`: use openssl to run a non-production ocsp responder for the ica
- `make query_ocsp_server`: use openssl to query the ocsp status of the server cert
