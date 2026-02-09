FROM python:3.12-slim AS testrunner

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    libxml2-dev \
    libxslt1-dev \
    libevent-dev \
    libsasl2-dev \
    libldap2-dev \
    libpq-dev \
    postgresql-client \
    libjpeg-dev \
    zlib1g-dev \
    libfreetype6-dev \
    liblcms2-dev \
    libwebp-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libxcb1-dev \
    libffi-dev \
    libssl-dev \
    libxmlsec1 \
    libxmlsec1-dev \
    && rm -rf /var/lib/apt/lists/*

RUN apt update
RUN apt install xmlsec1 -y

# Create odoo user and directories
RUN useradd -ms /bin/bash odoo
RUN mkdir -p /opt/odoo && chown -R odoo:odoo /opt/odoo

# Set working directory
WORKDIR /opt/odoo

# Copy base and enterprise folders
COPY --chown=odoo:odoo base/ /opt/odoo/base/
COPY --chown=odoo:odoo enterprise/ /opt/odoo/enterprise/

# Install Python dependencies
RUN pip install --no-cache-dir -r /opt/odoo/base/requirements.txt

# Install manifestoo for OCA-style addon discovery
RUN pip install --no-cache-dir manifestoo

# Install cryptography and related packages with proper compilation
RUN pip install --upgrade pip
RUN pip install --upgrade urllib3
RUN pip install "cryptography==37.0.0" "pyopenssl==22.0.0"
RUN pip install PyPDF2 phonenumbers fixedwidth pymongo dbfread

COPY --chown=odoo:odoo addons/symple_addons /opt/odoo/symple_addons
RUN find /opt/odoo/symple_addons -name "requirements.txt" -exec pip install --no-cache-dir -r {} \; 2>/dev/null

# Set entrypoint script
# Copy odoo configuration and entrypoint
COPY --chown=odoo:odoo odoo.conf /opt/odoo/odoo.conf
COPY --chown=odoo:odoo entrypoint.sh /opt/odoo/entrypoint.sh

WORKDIR /opt/odoo/addons
USER odoo
ENTRYPOINT ["/opt/odoo/entrypoint.sh"]

# Set default command (empty, entrypoint handles everything)
CMD []
