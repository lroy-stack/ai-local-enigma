#!/bin/bash

# =====================================================
# CONFIGURACIÓN SSL PARA NEO4J EN VPS
# Genera certificados y configura Neo4j para HTTPS
# =====================================================

set -e

echo "🔒 ============================================="
echo "   CONFIGURANDO SSL PARA NEO4J"
echo "==============================================="

# Leer configuración del .env
if [ -f ".env" ]; then
    source .env
    echo "✅ Variables cargadas desde .env"
else
    echo "⚠️  Archivo .env no encontrado, usando valores por defecto"
    NEO4J_HOSTNAME="neural.enigmaconalma.com"
fi

# Crear directorios necesarios
echo "📁 Creando estructura de directorios..."
mkdir -p ./neo4j/ssl/bolt/trusted
mkdir -p ./neo4j/ssl/bolt/revoked
mkdir -p ./neo4j/ssl/https/trusted
mkdir -p ./neo4j/ssl/https/revoked
mkdir -p ./neo4j/config

echo "✅ Directorios creados"

# ==========================================
# GENERAR CERTIFICADOS SSL
# ==========================================

generate_certificate() {
    local cert_type=$1
    local cert_path="./neo4j/ssl/${cert_type}"
    
    if [ ! -f "${cert_path}/neo4j.cert" ]; then
        echo "🔐 Generando certificado ${cert_type} para ${NEO4J_HOSTNAME}..."
        
        # Generar clave privada
        openssl genrsa -out "${cert_path}/neo4j.key" 2048
        
        # Crear archivo de configuración para certificado con SAN
        cat > "${cert_path}/cert.conf" << EOF
[req]
default_bits = 2048
prompt = no
distinguished_name = dn
req_extensions = v3_req

[dn]
C=ES
ST=Madrid
L=Madrid
O=Enigma Cocina Con Alma
CN=${NEO4J_HOSTNAME}

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${NEO4J_HOSTNAME}
DNS.2 = localhost
DNS.3 = neo4j
IP.1 = 127.0.0.1
EOF
        
        # Generar certificado con SAN
        openssl req -new -x509 -key "${cert_path}/neo4j.key" \
            -out "${cert_path}/neo4j.cert" \
            -days 365 \
            -config "${cert_path}/cert.conf" \
            -extensions v3_req
        
        # Configurar permisos
        chmod 600 "${cert_path}/neo4j.key"
        chmod 644 "${cert_path}/neo4j.cert"
        
        # Limpiar archivo temporal
        rm "${cert_path}/cert.conf"
        
        echo "  ✅ Certificado ${cert_type} generado"
    else
        echo "  ✅ Certificado ${cert_type} ya existe"
    fi
}

# Generar certificados para ambos protocolos
generate_certificate "bolt"
generate_certificate "https"

# ==========================================
# CONFIGURAR NEO4J
# ==========================================

echo ""
echo "⚙️  Configurando Neo4j para SSL..."

# Verificar si neo4j.conf ya existe y está configurado
if [ -f "./neo4j/config/neo4j.conf" ]; then
    echo "  📄 neo4j.conf ya existe, verificando configuración SSL..."
    
    if grep -q "server.https.enabled=true" "./neo4j/config/neo4j.conf"; then
        echo "  ✅ SSL ya configurado en neo4j.conf"
    else
        echo "  🔧 Agregando configuración SSL a neo4j.conf existente..."
        # Agregar configuración SSL al archivo existente
        cat >> ./neo4j/config/neo4j.conf << 'EOF'

# ==========================================
# CONFIGURACIÓN SSL AGREGADA AUTOMÁTICAMENTE
# ==========================================

# HTTPS Configuration
server.https.enabled=true
server.https.port=7473
dbms.ssl.policy.https.enabled=true
dbms.ssl.policy.https.base_directory=/ssl/https
dbms.ssl.policy.https.private_key=neo4j.key
dbms.ssl.policy.https.public_certificate=neo4j.cert

# Bolt SSL Configuration
server.bolt.tls_level=OPTIONAL
dbms.ssl.policy.bolt.enabled=true
dbms.ssl.policy.bolt.base_directory=/ssl/bolt
dbms.ssl.policy.bolt.private_key=neo4j.key
dbms.ssl.policy.bolt.public_certificate=neo4j.cert

# Connector Configuration
server.default_listen_address=0.0.0.0
server.default_advertised_address=${NEO4J_HOSTNAME}

# Disable HTTP (force HTTPS)
server.http.enabled=false
EOF
        echo "  ✅ Configuración SSL agregada"
    fi
else
    echo "  📝 Creando neo4j.conf con configuración SSL..."
    # Crear archivo de configuración completo
    cat > ./neo4j/config/neo4j.conf << EOF
# =====================================================
# NEO4J CONFIGURATION - ENIGMA COCINA CON ALMA
# Configuración SSL para VPS
# =====================================================

# Database Configuration
server.default_database=neo4j
dbms.default_database=neo4j

# Memory Configuration
server.memory.heap.initial_size=512m
server.memory.heap.max_size=1g
server.memory.pagecache.size=256m

# Network Configuration
server.default_listen_address=0.0.0.0
server.default_advertised_address=${NEO4J_HOSTNAME}

# HTTP Configuration (disabled for security)
server.http.enabled=false

# HTTPS Configuration
server.https.enabled=true
server.https.port=7473
dbms.ssl.policy.https.enabled=true
dbms.ssl.policy.https.base_directory=/ssl/https
dbms.ssl.policy.https.private_key=neo4j.key
dbms.ssl.policy.https.public_certificate=neo4j.cert

# Bolt Configuration
server.bolt.enabled=true
server.bolt.port=7687
server.bolt.tls_level=OPTIONAL

# Bolt SSL Configuration
dbms.ssl.policy.bolt.enabled=true
dbms.ssl.policy.bolt.base_directory=/ssl/bolt
dbms.ssl.policy.bolt.private_key=neo4j.key
dbms.ssl.policy.bolt.public_certificate=neo4j.cert

# Security Configuration
dbms.security.auth_enabled=true
dbms.security.procedures.unrestricted=apoc.*,gds.*

# Logging
dbms.logs.query.enabled=true
dbms.logs.query.threshold=1s

# Browser Configuration
browser.remote_content_hostname_whitelist=*
browser.credential_timeout=0
browser.retain_connection_credentials=true

# APOC Configuration
apoc.export.file.enabled=true
apoc.import.file.enabled=true
apoc.import.file.use_neo4j_config=true
EOF
    echo "  ✅ neo4j.conf creado con SSL"
fi

# ==========================================
# VERIFICACIÓN FINAL
# ==========================================

echo ""
echo "🔍 Verificando configuración..."

# Verificar que los certificados existen
cert_check=true
for cert_type in "bolt" "https"; do
    if [ -f "./neo4j/ssl/${cert_type}/neo4j.cert" ] && [ -f "./neo4j/ssl/${cert_type}/neo4j.key" ]; then
        echo "  ✅ Certificados ${cert_type} presentes"
    else
        echo "  ❌ Certificados ${cert_type} faltantes"
        cert_check=false
    fi
done

# Verificar configuración
if [ -f "./neo4j/config/neo4j.conf" ] && grep -q "server.https.enabled=true" "./neo4j/config/neo4j.conf"; then
    echo "  ✅ Configuración neo4j.conf correcta"
else
    echo "  ❌ Configuración neo4j.conf incorrecta"
    cert_check=false
fi

# ==========================================
# RESUMEN
# ==========================================

echo ""
echo "🎉 ============================================="
echo "   CONFIGURACIÓN SSL COMPLETADA"
echo "==============================================="
echo ""

if [ "$cert_check" = true ]; then
    echo "✅ ESTADO: SSL configurado correctamente"
    echo ""
    echo "🔗 ACCESO SSL CONFIGURADO:"
    echo "   • Neo4j Browser: https://${NEO4J_HOSTNAME}:7473"
    echo "   • Bolt SSL:      bolt+s://${NEO4J_HOSTNAME}:7687"
    echo "   • Bolt inseguro: bolt://${NEO4J_HOSTNAME}:7687"
    echo ""
    echo "🚀 PRÓXIMOS PASOS:"
    echo "   1. Iniciar servicios: python3 start_services.py --profile cpu --environment public"
    echo "   2. Verificar acceso HTTPS después de que Caddy genere certificados"
    echo "   3. Los certificados Neo4j son auto-firmados (normal para uso interno)"
    echo ""
    echo "⚠️  NOTAS IMPORTANTES:"
    echo "   • Neo4j usará certificados auto-firmados (seguro pero con warning en browser)"
    echo "   • Caddy maneja SSL público, Neo4j maneja SSL interno"
    echo "   • Puedes aceptar el certificado auto-firmado en el browser"
else
    echo "❌ ESTADO: Errores en configuración SSL"
    echo "   Revisa los errores anteriores y ejecuta de nuevo"
fi

echo ""
echo "🔒 ¡SSL Neo4j configurado para VPS!"