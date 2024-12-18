
# keep all intermediate results
.SECONDARY:

SHELL=bash

#
# overrideable by envvars.
#

NAMESPACE?=branch-$(shell git rev-parse --abbrev-ref HEAD)
EXTRA_DOCKER_FLAGS?=--interactive # --tty

CA?=root-trustedcert
CA_ENCRYPT_PASSWORD?=Password123
CA_EXPORT_PASSWORD?=Password123
CA_YEARS?=30
CA_DAYS?=$(shell echo $$((${CA_YEARS} * 365)))
CA_SUBJ_C?=US
CA_SUBJ_ST?=California
CA_SUBJ_L?=San Francisco
CA_SUBJ_O?=TrustedCert, Inc.
CA_SUBJ_OU?=Certificate Authority Division
CA_SUBJ_CN?=TrustedCert Root CA
CA_SUBJ_EMAIL?=admin@${CA}.com

ICA?=ica-securetrust
ICA_ENCRYPT_PASSWORD?=Password321
ICA_YEARS?=15
ICA_DAYS?=$(shell echo $$((${ICA_YEARS} * 365)))
ICA_SUBJ_C?=US
ICA_SUBJ_ST?=New York
ICA_SUBJ_L?=New York City
ICA_SUBJ_O?=SecureTrust, Ltd.
ICA_SUBJ_OU?=Intermediate Ceritificate Authority Operations
ICA_SUBJ_CN?=SecureTrust Intermediate CA
ICA_SUBJ_EMAIL?=admin@${ICA}.com

OCSP?=ocsp-${ICA}
OCSP_ENCRYPT_PASSWORD?=Ocsp123
OCSP_EXPORT_PASSWORD?=Ocsp123
OCSP_YEARS?=2
OCSP_DAYS?=$(shell echo $$((${SERVER_YEARS} * 365)))
OCSP_SUBJ_C?=${ICA_SUBJ_C}
OCSP_SUBJ_ST?=${ICA_SUBJ_ST}
OCSP_SUBJ_L?=${ICA_SUBJ_L}
OCSP_SUBJ_O?=${ICA_SUBJ_O}
OCSP_SUBJ_OU?=OCSP Services
OCSP_SUBJ_CN?=SecureTrust Intermediate OCSP
OCSP_SUBJ_EMAIL?=revocations@${ICA}.com

SERVER?=server-cortexa
SERVER_ENCRYPT_PASSWORD?=Password456
SERVER_YEARS?=2
SERVER_DAYS?=$(shell echo $$((${SERVER_YEARS} * 365)))
SERVER_SUBJ_C?=US
SERVER_SUBJ_ST?=California
SERVER_SUBJ_L?=Fremont
SERVER_SUBJ_O?=Cortexa Solutions, Inc.
SERVER_SUBJ_OU?=Web Security Services
SERVER_SUBJ_CN?=www.${SERVER}.com
SERVER_SUBJ_EMAIL?=admin@${SERVER}.com
SERVER_QUALIFIED=qualified

USR?=user-mdubois
USR_ENCRYPT_PASSWORD?=Password654
USR_YEARS?=2
USR_DAYS?=$(shell echo $$((${USR_YEARS} * 365)))
USR_SUBJ_C?=FR
USR_SUBJ_ST?=Ile De France
USR_SUBJ_L?=Paris
USR_SUBJ_O?=Cortexa Solutions
USR_SUBJ_OU?=Corporate Access
USR_SUBJ_CN?=Marie Dubois
USR_SUBJ_EMAIL?=${USR}@${SERVER_SUBJ_CN}

OPENSSL_VERSION?=3.1.4

# ocsp vars
REVOCATION_PUBLISH_STRATEGY?=ocsp # one of { crl, ocsp }
OCSP_RESPONDER_PORT?=2560
RANDOM_PORT:=$(shell shuf -i 1024-65535 -n 1)
OCSP_HOST?=${NAMESPACE}-${ICA}-ocsp
NETWORK?=makefile-pki
OCSP_PORT_MAPPING?=$(strip $(shell docker container inspect --format='{{(index (index .NetworkSettings.Ports "${OCSP_RESPONDER_PORT}/tcp") 0).HostPort}}' ${OCSP_HOST} 2>/dev/null || echo "${RANDOM_PORT}"))

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
ocsp_export: dest/${NAMESPACE}/${OCSP}/private/ocsp.key.p12

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
	dest/${NAMESPACE}/${OCSP}/ocsp.cert.pem \
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
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} ca \
			-config dest/${NAMESPACE}/${ICA}/ica.cnf \
			-passin pass:${ICA_ENCRYPT_PASSWORD} \
			-revoke dest/${NAMESPACE}/${SERVER}/server.cert.pem
	-rm dest/${NAMESPACE}/${SERVER}/server.csr.pem
	touch dest/${NAMESPACE}/${ICA}/.crldirty

.PHONY: ica_crl ## generate a new CRL list. revocations don't show up in the CRL until it is manually rerun
ica_crl: dest/${NAMESPACE}/${ICA}/ica.crl.pem

.PHONY: verify_intermediate
verify_intermediate: dest/${NAMESPACE}/${ICA}/ica.cert.pem
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} verify -CAfile dest/${NAMESPACE}/${CA}/ca.cert.pem $<

.PHONY: verify_ocsp ## use openssl to validate the ocsp cert was correctly signed without checking revocation status
verify_ocsp: dest/${NAMESPACE}/${OCSP}/ocsp.cert.pem
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} verify -CAfile dest/${NAMESPACE}/${ICA}/ica-chain.cert.pem $<

.PHONY: verify_server ## use openssl to validate the server cert was correctly signed without checking revocation status
verify_server: dest/${NAMESPACE}/${SERVER}/server.cert.pem
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} verify -CAfile dest/${NAMESPACE}/${ICA}/ica-chain.cert.pem $<

.PHONY: verify_usr
verify_usr: dest/${NAMESPACE}/${USR}/usr.cert.pem
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} verify -CAfile dest/${NAMESPACE}/${ICA}/ica-chain.cert.pem $<

.PHONY: dump_ca
dump_ca:
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} x509 -text -noout -in dest/${NAMESPACE}/${CA}/ca.cert.pem 

.PHONY: dump_ica
dump_ica:
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} x509 -text -noout -in dest/${NAMESPACE}/${ICA}/ica.cert.pem 

.PHONY: dump_server ## use openssl to print a text representation of the server cert
dump_server:
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} x509 -text -noout -in dest/${NAMESPACE}/${SERVER}/server.cert.pem 

.PHONY: dump_usr
dump_usr:
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} x509 -text -noout -in dest/${NAMESPACE}/${USR}/usr.cert.pem 

.PHONY: dump_ica_crl ## use openssl to print a text representation of the current crl
dump_ica_crl:
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		openssl crl -in dest/${NAMESPACE}/${ICA}/ica.crl.pem -noout -text

.PHONY: serve_ica_ocsp ## use openssl to run a non-production ocsp responder for the ica
serve_ica_ocsp: ocsp-network
	docker run ${EXTRA_DOCKER_FLAGS} \
		--name "${OCSP_HOST}" \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		--network '${NETWORK}' \
		--publish ${OCSP_PORT_MAPPING}:${OCSP_RESPONDER_PORT} \
		alpine/openssl:${OPENSSL_VERSION} ocsp \
			-CApath dest/${NAMESPACE}/${ICA}/certs \
			-index dest/${NAMESPACE}/${ICA}/index.txt \
			-port ${OCSP_RESPONDER_PORT} \
			-CA dest/${NAMESPACE}/${ICA}/ica-chain.cert.pem \
			-rkey dest/${NAMESPACE}/${ICA}/private/ica.key.pem \
			-rsigner dest/${NAMESPACE}/${ICA}/ica.cert.pem \
			-passin pass:${ICA_ENCRYPT_PASSWORD} \
			-text

.PHONY: query_ocsp_server ## use openssl to query the ocsp status of the server cert
query_ocsp_server: ocsp-network
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--network '${NETWORK}' \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} ocsp \
			-CAfile dest/${NAMESPACE}/${ICA}/ica-chain.cert.pem \
			-url http://${OCSP_HOST}:${OCSP_RESPONDER_PORT} -resp_text \
			-issuer dest/${NAMESPACE}/${ICA}/ica.cert.pem \
			-cert dest/${NAMESPACE}/${SERVER}/server.cert.pem

.PHONY: ocsp-network
ocsp-network:
	docker network inspect \
		--format 'docker network ${NETWORK} was created on {{.Created}}' \
		${NETWORK} || docker network create ${NETWORK}

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
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} genrsa -aes256 -passout pass:${CA_ENCRYPT_PASSWORD} -out $@ 4096
	chmod 400 $@

dest/%/private/ca.key.p12: dest/%/private/ca.key.pem dest/%/ca.cert.pem
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} pkcs12 \
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
	echo '{"policy": "policy_strict", "ca_type": "ca", "dest_dir": "${PWD}/$(@D)"}' | \
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		toolbelt/mustache - template.cnf > $@

dest/%/ca.cert.pem: dest/%/private/ca.key.pem dest/%/ca.cnf
	mkdir -p $(@D)
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} req -config $(@D)/ca.cnf \
			-key $< \
			-new -notext -x509 -days ${CA_DAYS} -sha256 -extensions v3_ca \
			-passin pass:${CA_ENCRYPT_PASSWORD} \
			-subj "/C=${CA_SUBJ_C}/ST=${CA_SUBJ_ST}/L=${CA_SUBJ_L}/O=${CA_SUBJ_O}/OU=${CA_SUBJ_OU}/CN=${CA_SUBJ_CN}/emailAddress=${CA_SUBJ_EMAIL}" \
			-out $@
	chmod 444 $@

# ica files
dest/%/ica.cnf: template.cnf
	mkdir -p $(@D)
	echo '{"policy": "policy_loose", "ca_type": "ica", "dest_dir": "${PWD}/$(@D)"}' | \
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		toolbelt/mustache - template.cnf > $@

dest/%/private/ica.key.pem:
	mkdir -p $(@D)
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} genrsa -aes256 -passout pass:${ICA_ENCRYPT_PASSWORD} -out $@ 4096
	chmod 400 $@

dest/%/ica.csr.pem: dest/%/private/ica.key.pem dest/%/ica.cnf
	mkdir -p $(@D)
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} req -config $(@D)/ica.cnf \
			-new -sha256 \
			-key $< \
			-passin pass:${ICA_ENCRYPT_PASSWORD} \
			-subj "/C=${ICA_SUBJ_C}/ST=${ICA_SUBJ_ST}/L=${ICA_SUBJ_L}/O=${ICA_SUBJ_O}/OU=${ICA_SUBJ_OU}/CN=${ICA_SUBJ_CN}/emailAddress=${ICA_SUBJ_EMAIL}" \
			-out $@

dest/%/ica.cert.pem: dest/%/ica.csr.pem
	mkdir -p $(@D)
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} ca -config dest/${NAMESPACE}/${CA}/ca.cnf \
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
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		openssl ca -config dest/${NAMESPACE}/${ICA}/ica.cnf \
			-passin pass:${ICA_ENCRYPT_PASSWORD} \
			-gencrl \
			-out $@

# server files
dest/%/server.cnf: template.cnf
	mkdir -p $(@D)
	echo '{"policy": "policy_loose", "ca_type": "server", "dest_dir": "${PWD}/$(@D)"}' | \
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		toolbelt/mustache - template.cnf > $@

dest/%/private/server.key.pem:
	mkdir -p $(@D)
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} genrsa -aes256 -passout pass:${SERVER_ENCRYPT_PASSWORD} -out $@ 2048
	chmod 400 $@

dest/%/server.csr.pem: dest/%/private/server.key.pem dest/%/server.cnf
	mkdir -p $(@D)
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} req -config $(@D)/server.cnf \
			-new -sha256 \
			-key $< \
			-passin pass:${SERVER_ENCRYPT_PASSWORD} \
			-subj "/C=${SERVER_SUBJ_C}/ST=${SERVER_SUBJ_ST}/L=${SERVER_SUBJ_L}/O=${SERVER_SUBJ_O}/OU=${SERVER_SUBJ_OU}/CN=${SERVER_SUBJ_CN}/emailAddress=${SERVER_SUBJ_EMAIL}" \
			-out $@

dest/%/server.cert.pem: dest/%/server.csr.pem
	mkdir -p $(@D)
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} ca -config dest/${NAMESPACE}/${ICA}/ica.cnf \
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
	echo '{"policy": "policy_loose", "ca_type": "ocsp", "dest_dir": "${PWD}/$(@D)"}' | \
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		toolbelt/mustache - template.cnf > $@

dest/%/private/ocsp.key.pem:
	mkdir -p $(@D)
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} genrsa -aes256 -passout pass:${OCSP_ENCRYPT_PASSWORD} -out $@ 2048
	chmod 400 $@

dest/%/private/ocsp.key.p12: dest/%/private/ocsp.key.pem dest/%/ocsp.cert.pem
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} pkcs12 \
			-export \
			-in dest/$*/ocsp.cert.pem \
			-inkey $< \
			-out $@ \
			-passin pass:${OCSP_ENCRYPT_PASSWORD} \
			-password pass:${OCSP_EXPORT_PASSWORD}
	chmod 400 $@

dest/%/ocsp.csr.pem: dest/%/private/ocsp.key.pem dest/%/ocsp.cnf
	mkdir -p $(@D)
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} req \
			-config $(@D)/ocsp.cnf \
			-new -sha256 \
			-key $< \
			-passin pass:${OCSP_ENCRYPT_PASSWORD} \
			-subj "/C=${OCSP_SUBJ_C}/ST=${OCSP_SUBJ_ST}/L=${OCSP_SUBJ_L}/O=${OCSP_SUBJ_O}/OU=${OCSP_SUBJ_OU}/CN=${OCSP_SUBJ_CN}/emailAddress=${OCSP_SUBJ_EMAIL}" \
			-out $@

dest/%/ocsp.cert.pem: dest/%/ocsp.csr.pem
	mkdir -p $(@D)
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} ca \
			-config dest/${NAMESPACE}/${ICA}/ica.cnf \
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
	echo '{"policy": "policy_loose", "ca_type": "usr", "dest_dir": "${PWD}/$(@D)"}' | \
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		toolbelt/mustache - template.cnf > $@

dest/%/private/usr.key.pem:
	mkdir -p $(@D)
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} genrsa -aes256 -passout pass:${USR_ENCRYPT_PASSWORD} -out $@ 2048
	chmod 400 $@

dest/%/usr.csr.pem: dest/%/private/usr.key.pem dest/%/usr.cnf
	mkdir -p $(@D)
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} req \
			-config $(@D)/usr.cnf \
			-new -sha256 \
			-key $< \
			-passin pass:${USR_ENCRYPT_PASSWORD} \
			-subj "/C=${USR_SUBJ_C}/ST=${USR_SUBJ_ST}/L=${USR_SUBJ_L}/O=${USR_SUBJ_O}/OU=${USR_SUBJ_OU}/CN=${USR_SUBJ_CN}/emailAddress=${USR_SUBJ_EMAIL}" \
			-out $@

dest/%/usr.cert.pem: dest/%/usr.csr.pem
	mkdir -p $(@D)
	docker run ${EXTRA_DOCKER_FLAGS} \
		--rm \
		--volume "${PWD}":"${PWD}" \
		--workdir "${PWD}" \
		alpine/openssl:${OPENSSL_VERSION} ca \
			-config dest/${NAMESPACE}/${ICA}/ica.cnf \
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

