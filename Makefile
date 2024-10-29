
# keep all intermediate results
.SECONDARY:

NAMESPACE?=sandbox

REVOCATION_PUBLISH_STRATEGY?=ocsp # one of { crl, ocsp }
OCSP_RESPONDER_PORT?=2560

CA?=fakeca
CA_ENCRYPT_PASSWORD?=Password123
CA_EXPORT_PASSWORD?=Password123
CA_YEARS?=30
CA_DAYS?=$(shell echo $$((${CA_YEARS} * 365)))
CA_SUBJ_C?=US
CA_SUBJ_ST?=Utah
CA_SUBJ_L?=Lehi
CA_SUBJ_O?=Digicert
CA_SUBJ_OU?=Engineering
CA_SUBJ_CN?=${CA}.com
CA_SUBJ_EMAIL?=admin@${CA_SUBJ_CN}

ICA?=dotrustitco
ICA_ENCRYPT_PASSWORD?=Password321
ICA_YEARS?=15
ICA_DAYS?=$(shell echo $$((${ICA_YEARS} * 365)))
ICA_SUBJ_C?=US
ICA_SUBJ_ST?=Utah
ICA_SUBJ_L?=Lehi
ICA_SUBJ_O?=Digicert
ICA_SUBJ_OU?=Engineering
ICA_SUBJ_CN?=${ICA}.com
ICA_SUBJ_EMAIL?=admin@${ICA_SUBJ_CN}

OCSP?=ocsp
OCSP_ENCRYPT_PASSWORD?=Ocsp123
OCSP_EXPORT_PASSWORD?=Ocsp123
OCSP_YEARS?=2
OCSP_DAYS?=$(shell echo $$((${SERVER_YEARS} * 365)))
OCSP_SUBJ_C?=US
OCSP_SUBJ_ST?=Utah
OCSP_SUBJ_L?=Lehi
OCSP_SUBJ_O?=Digicert
OCSP_SUBJ_OU?=Engineering
OCSP_SUBJ_CN?=${SERVER}.com
OCSP_SUBJ_EMAIL?=admin@${SERVER_SUBJ_CN}

SERVER?=example
SERVER_ENCRYPT_PASSWORD?=Password456
SERVER_YEARS?=2
SERVER_DAYS?=$(shell echo $$((${SERVER_YEARS} * 365)))
SERVER_SUBJ_C?=US
SERVER_SUBJ_ST?=Utah
SERVER_SUBJ_L?=Lehi
SERVER_SUBJ_O?=Digicert
SERVER_SUBJ_OU?=Engineering
SERVER_SUBJ_CN?=${SERVER}.com
SERVER_SUBJ_EMAIL?=admin@${SERVER_SUBJ_CN}
SERVER_QUALIFIED=qualified

USR?=bob
USR_ENCRYPT_PASSWORD?=Password654
USR_YEARS?=2
USR_DAYS?=$(shell echo $$((${USR_YEARS} * 365)))
USR_SUBJ_C?=US
USR_SUBJ_ST?=Utah
USR_SUBJ_L?=Lehi
USR_SUBJ_O?=Digicert
USR_SUBJ_OU?=Engineering
USR_SUBJ_CN?=${USR}@${SERVER_SUBJ_CN}
USR_SUBJ_EMAIL?=${USR_SUBJ_CN}

.PHONY: help ## Show this help.
help:
	@echo "# Make Commands:"
	@cat Makefile | grep '^.PHONY: [a-z]*.*##' | sed 's/.PHONY: \(.*\) ##\(.*\)/- `make \1`:\2/'

.PHONY: clean ## recursively remove all files from the destination namespace.
clean:
	rm -fr dest/${NAMESPACE}

.PHONY: ca ## generate files for a ca: openssl db files, private keys, config file, etd...
ca: \
	dest/${NAMESPACE}/${CA}/index.txt \
	dest/${NAMESPACE}/${CA}/serial \
	dest/${NAMESPACE}/${CA}/crlnumber \
	dest/${NAMESPACE}/${CA}/ca.cert.pem

.PHONY: ca_export ## generate pkcs12 file for export.
ca_export: dest/${NAMESPACE}/${CA}/private/ca.key.p12

.PHONY: ocsp_export ## generate pkcs12 file for export.
ocsp_export: dest/${NAMESPACE}/${ICA}/${OCSP}/private/ocsp.key.p12

.PHONY: ica ## use ca to sign ica cert and generates its files
ica: \
	ca \
	dest/${NAMESPACE}/${ICA}/index.txt\
	dest/${NAMESPACE}/${ICA}/serial \
	dest/${NAMESPACE}/${ICA}/crlnumber \
	dest/${NAMESPACE}/${ICA}/ica.cert.pem \
	dest/${NAMESPACE}/${ICA}/ica-chain.cert.pem \
	verify_intermediate

.PHONY: ocsp ## use ica to sign ocsp cert and generate private key
ocsp: \
	ica \
	dest/${NAMESPACE}/${ICA}/${OCSP}/ocsp.cert.pem \
	verify_ocsp

.PHONY: server ## use ica to sign server cert and generate private key
server: \
	ica \
	dest/${NAMESPACE}/${SERVER}/server.cert.pem \
	verify_server

.PHONY: usr ## use ica to sign user cert and generate private key
usr: \
	ica \
	dest/${NAMESPACE}/${USR}/usr.cert.pem \
	verify_usr

.PHONY: revoke_server ## revoke a server cert
revoke_server:
	openssl ca \
		-config dest/${NAMESPACE}/${ICA}/ica.cnf \
		-passin pass:${ICA_ENCRYPT_PASSWORD} \
		-revoke dest/${NAMESPACE}/${SERVER}/server.cert.pem
	-rm dest/${NAMESPACE}/${SERVER}/server.csr.pem
	touch dest/${NAMESPACE}/${ICA}/.crldirty

.PHONY: ica_crl ## generate a new CRL list. revocations don't show up in the CRL until it is manually rerun
ica_crl: dest/${NAMESPACE}/${ICA}/ica.crl.pem

.PHONY: verify_intermediate
verify_intermediate: dest/${NAMESPACE}/${ICA}/ica.cert.pem
	openssl verify -CAfile dest/${NAMESPACE}/${CA}/ca.cert.pem $<

.PHONY: verify_ocsp ## use openssl to validate the ocsp cert was correctly signed without checking revocation status
verify_ocsp: dest/${NAMESPACE}/${ICA}/${OCSP}/ocsp.cert.pem
	openssl verify -CAfile dest/${NAMESPACE}/${ICA}/ica-chain.cert.pem $<

.PHONY: verify_server ## use openssl to validate the server cert was correctly signed without checking revocation status
verify_server: dest/${NAMESPACE}/${SERVER}/server.cert.pem
	openssl verify -CAfile dest/${NAMESPACE}/${ICA}/ica-chain.cert.pem $<

.PHONY: verify_usr
verify_usr: dest/${NAMESPACE}/${USR}/usr.cert.pem
	openssl verify -CAfile dest/${NAMESPACE}/${ICA}/ica-chain.cert.pem $<

.PHONY: dump_ca
dump_ca:
	openssl x509 -text -noout -in dest/${NAMESPACE}/${CA}/ca.cert.pem 

.PHONY: dump_ica
dump_ica:
	openssl x509 -text -noout -in dest/${NAMESPACE}/${ICA}/ica.cert.pem 

.PHONY: dump_server ## use openssl to print a text representation of the server cert
dump_server:
	openssl x509 -text -noout -in dest/${NAMESPACE}/${SERVER}/server.cert.pem 

.PHONY: dump_usr
dump_usr:
	openssl x509 -text -noout -in dest/${NAMESPACE}/${USR}/usr.cert.pem 

.PHONY: dump_ica_crl ## use openssl to print a text representation of the current crl
dump_ica_crl:
	openssl crl -in dest/${NAMESPACE}/${ICA}/ica.crl.pem -noout -text

.PHONY: serve_ica_ocsp ## use openssl to run a non-production ocsp responder for the ica
serve_ica_ocsp:
	openssl ocsp \
		-CApath dest/${NAMESPACE}/${ICA}/certs \
		-index dest/${NAMESPACE}/${ICA}/index.txt \
		-port ${OCSP_RESPONDER_PORT} \
		-CA dest/${NAMESPACE}/${ICA}/ica-chain.cert.pem \
		-rkey dest/${NAMESPACE}/${ICA}/private/ica.key.pem \
		-rsigner dest/${NAMESPACE}/${ICA}/ica.cert.pem \
		-passin pass:${ICA_ENCRYPT_PASSWORD} \
		-text

.PHONY: query_ocsp_server ## use openssl to query the ocsp status of the server cert
query_ocsp_server:
	openssl ocsp \
		-CAfile dest/${NAMESPACE}/${ICA}/ica-chain.cert.pem \
		-url http://127.0.0.1:${OCSP_RESPONDER_PORT} -resp_text \
		-issuer dest/${NAMESPACE}/${ICA}/ica.cert.pem \
		-cert dest/${NAMESPACE}/${SERVER}/server.cert.pem

# common openssl database files
dest/%/crlnumber:
	mkdir -p $(@D)
	echo 1000 > $@
	touch $(@D)/.crldirty

dest/%/index.txt:
	mkdir -p $(@D)/certs
	touch $@

dest/%/serial:
	mkdir -p $(@D)
	echo 1000 > $@

dest/%/private/ca.key.pem:
	mkdir -p $(@D)
	openssl genrsa -aes256 -passout pass:${CA_ENCRYPT_PASSWORD} -out $@ 4096
	chmod 400 $@

dest/%/private/ca.key.p12: dest/%/private/ca.key.pem dest/%/ca.cert.pem
	openssl pkcs12 \
		-export \
		-in dest/${NAMESPACE}/${CA}/ca.cert.pem \
		-inkey $< \
		-out $@ \
		-passin pass:${CA_ENCRYPT_PASSWORD} \
		-password pass:${CA_EXPORT_PASSWORD}
		chmod 400 $@

# ca files
dest/%/ca.cnf: template.cnf dest/%/private/ca.key.pem
	mkdir -p $(@D)
	POLICY=policy_strict CA_TYPE=ca DEST_DIR=${PWD}/$(@D) envsubst -i template.cnf -o $@

dest/%/ca.cert.pem: dest/%/private/ca.key.pem dest/%/ca.cnf
	mkdir -p $(@D)
	openssl req -config $(@D)/ca.cnf \
		-key $< \
		-new -notext -x509 -days ${CA_DAYS} -sha256 -extensions v3_ca \
		-passin pass:${CA_ENCRYPT_PASSWORD} \
		-subj "/C=${CA_SUBJ_C}/ST=${CA_SUBJ_ST}/L=${CA_SUBJ_L}/O=${CA_SUBJ_O}/OU=${CA_SUBJ_OU}/CN=${CA_SUBJ_CN}/emailAddress=${CA_SUBJ_EMAIL}" \
		-out $@
	chmod 444 $@

# ica files
dest/%/ica.cnf: template.cnf
	mkdir -p $(@D)
	CRL_HOST=${ICA_SUBJ_CN} POLICY=policy_loose CA_TYPE=ica DEST_DIR=${PWD}/$(@D) envsubst -i template.cnf -o $@

dest/%/private/ica.key.pem:
	mkdir -p $(@D)
	openssl genrsa -aes256 -passout pass:${ICA_ENCRYPT_PASSWORD} -out $@ 4096
	chmod 400 $@

dest/%/ica.csr.pem: dest/%/private/ica.key.pem dest/%/ica.cnf
	mkdir -p $(@D)
	openssl req -config $(@D)/ica.cnf \
		-new -sha256 \
		-key $< \
		-passin pass:${ICA_ENCRYPT_PASSWORD} \
		-subj "/C=${ICA_SUBJ_C}/ST=${ICA_SUBJ_ST}/L=${ICA_SUBJ_L}/O=${ICA_SUBJ_O}/OU=${ICA_SUBJ_OU}/CN=${ICA_SUBJ_CN}/emailAddress=${ICA_SUBJ_EMAIL}" \
		-out $@

dest/%/ica.cert.pem: dest/%/ica.csr.pem
	mkdir -p $(@D)
	openssl ca -config dest/${NAMESPACE}/${CA}/ca.cnf \
		-batch \
		-days ${ICA_DAYS} -notext -md sha256 -extensions v3_intermediate_ca \
		-passin pass:${CA_ENCRYPT_PASSWORD} \
		-in $(@D)/ica.csr.pem \
		-out $@
	chmod 444 $@

dest/%/ica-chain.cert.pem: dest/${NAMESPACE}/${CA}/ca.cert.pem dest/%/ica.cert.pem
	mkdir -p $(@D)
	cat $^ > $@
	chmod 444 $@

dest/%/ica.crl.pem: dest/%/.crldirty
	mkdir -p $(@D)
	openssl ca -config dest/${NAMESPACE}/${ICA}/ica.cnf \
		-passin pass:${ICA_ENCRYPT_PASSWORD} \
		-gencrl \
		-out $@

# server files
dest/%/server.cnf: template.cnf
	mkdir -p $(@D)
	POLICY=policy_loose CA_TYPE=server DEST_DIR=${PWD}/$(@D) envsubst -i template.cnf -o $@

dest/%/private/server.key.pem:
	mkdir -p $(@D)
	openssl genrsa -aes256 -passout pass:${SERVER_ENCRYPT_PASSWORD} -out $@ 2048
	chmod 400 $@

dest/%/server.csr.pem: dest/%/private/server.key.pem dest/%/server.cnf
	mkdir -p $(@D)
	openssl req -config $(@D)/server.cnf \
		-new -sha256 \
		-key $< \
		-passin pass:${SERVER_ENCRYPT_PASSWORD} \
		-subj "/C=${SERVER_SUBJ_C}/ST=${SERVER_SUBJ_ST}/L=${SERVER_SUBJ_L}/O=${SERVER_SUBJ_O}/OU=${SERVER_SUBJ_OU}/CN=${SERVER_SUBJ_CN}/emailAddress=${SERVER_SUBJ_EMAIL}" \
		-out $@

dest/%/server.cert.pem: dest/%/server.csr.pem
	mkdir -p $(@D)
	openssl ca -config dest/${NAMESPACE}/${ICA}/ica.cnf \
		-batch \
		-days ${ICA_DAYS} -notext -md sha256 \
		-extensions server_cert \
		-extensions ${REVOCATION_PUBLISH_STRATEGY} \
		-extensions ${SERVER_QUALIFIED} \
		-passin pass:${ICA_ENCRYPT_PASSWORD} \
		-in $(@D)/server.csr.pem \
		-out $@
	chmod 444 $@

dest/%/server-chain.cert.pem: dest/${NAMESPACE}/${ICA}/ica-chain.cert.pem dest/%/server.cert.pem
	mkdir -p $(@D)
	cat $^ > $@
	chmod 444 $@

# ocsp files
dest/%/ocsp.cnf: template.cnf
	mkdir -p $(@D)
	POLICY=policy_loose CA_TYPE=ocsp DEST_DIR=${PWD}/$(@D) envsubst -i template.cnf -o $@

dest/%/private/ocsp.key.pem:
	mkdir -p $(@D)
	openssl genrsa -aes256 -passout pass:${OCSP_ENCRYPT_PASSWORD} -out $@ 2048
	chmod 400 $@

dest/%/private/ocsp.key.p12: dest/%/private/ocsp.key.pem dest/%/ocsp.cert.pem
	openssl pkcs12 \
		-export \
		-in dest/$*/ocsp.cert.pem \
		-inkey $< \
		-out $@ \
		-passin pass:${OCSP_ENCRYPT_PASSWORD} \
		-password pass:${OCSP_EXPORT_PASSWORD}
		chmod 400 $@

dest/%/ocsp.csr.pem: dest/%/private/ocsp.key.pem dest/%/ocsp.cnf
	mkdir -p $(@D)
	openssl req -config $(@D)/ocsp.cnf \
		-new -sha256 \
		-key $< \
		-passin pass:${OCSP_ENCRYPT_PASSWORD} \
		-subj "/C=${OCSP_SUBJ_C}/ST=${OCSP_SUBJ_ST}/L=${OCSP_SUBJ_L}/O=${OCSP_SUBJ_O}/OU=${OCSP_SUBJ_OU}/CN=${OCSP_SUBJ_CN}/emailAddress=${OCSP_SUBJ_EMAIL}" \
		-out $@

dest/%/ocsp.cert.pem: dest/%/ocsp.csr.pem
	mkdir -p $(@D)
	openssl ca -config dest/${NAMESPACE}/${ICA}/ica.cnf \
		-batch \
		-days ${ICA_DAYS} -notext -md sha256 \
		-extensions ocsp_cert \
		-passin pass:${ICA_ENCRYPT_PASSWORD} \
		-in $(@D)/ocsp.csr.pem \
		-out $@
	chmod 444 $@

dest/%/ocsp-chain.cert.pem: dest/${NAMESPACE}/${ICA}/ica-chain.cert.pem dest/%/ocsp.cert.pem
	mkdir -p $(@D)
	cat $^ > $@
	chmod 444 $@

# usr files
dest/%/usr.cnf: template.cnf
	mkdir -p $(@D)
	POLICY=policy_loose CA_TYPE=usr DEST_DIR=${PWD}/$(@D) envsubst -i template.cnf -o $@

dest/%/private/usr.key.pem:
	mkdir -p $(@D)
	openssl genrsa -aes256 -passout pass:${USR_ENCRYPT_PASSWORD} -out $@ 2048
	chmod 400 $@

dest/%/usr.csr.pem: dest/%/private/usr.key.pem dest/%/usr.cnf
	mkdir -p $(@D)
	openssl req -config $(@D)/usr.cnf \
		-new -sha256 \
		-key $< \
		-passin pass:${USR_ENCRYPT_PASSWORD} \
		-subj "/C=${USR_SUBJ_C}/ST=${USR_SUBJ_ST}/L=${USR_SUBJ_L}/O=${USR_SUBJ_O}/OU=${USR_SUBJ_OU}/CN=${USR_SUBJ_CN}/emailAddress=${USR_SUBJ_EMAIL}" \
		-out $@

dest/%/usr.cert.pem: dest/%/usr.csr.pem
	mkdir -p $(@D)
	openssl ca -config dest/${NAMESPACE}/${ICA}/ica.cnf \
		-batch \
		-days ${ICA_DAYS} -notext -md sha256 -extensions usr_cert \
		-passin pass:${ICA_ENCRYPT_PASSWORD} \
		-in $(@D)/usr.csr.pem \
		-out $@
	chmod 444 $@

dest/%/usr-chain.cert.pem: dest/${NAMESPACE}/${ICA}/ica-chain.cert.pem dest/%/usr.cert.pem
	mkdir -p $(@D)
	cat $^ > $@
	chmod 444 $@
