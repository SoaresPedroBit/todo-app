# Estação de controle do Ansible: o Ansible não roda nativamente no Windows, e
# assim a equipe e o GitHub Actions usam exatamente a mesma versão.
# O gcloud abre o túnel SSH pelo Identity-Aware Proxy.
FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:593.0.0-slim

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends openssh-client python3-venv >/dev/null \
 && rm -rf /var/lib/apt/lists/* \
 && python3 -m venv /opt/ansible \
 && /opt/ansible/bin/pip install -q --no-cache-dir ansible-core==2.17.14 \
 && /opt/ansible/bin/ansible-galaxy collection install -p /usr/share/ansible/collections ansible.posix:==1.6.2 community.docker:==4.8.1

ENV PATH="/opt/ansible/bin:${PATH}"
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["bash", "/usr/local/bin/entrypoint.sh"]
