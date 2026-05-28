# ============================================================================
# Build stage — compila el Flutter web con las credenciales de Supabase
# inyectadas vía build args.
#
# Coolify: configurar "Build Arguments" con SUPABASE_URL y SUPABASE_ANON_KEY
# (no como Environment Variables — el .env se necesita en build time porque
# flutter_dotenv los empaqueta como asset).
# ============================================================================
FROM ghcr.io/cirruslabs/flutter:stable AS build

ARG SUPABASE_URL
ARG SUPABASE_ANON_KEY

WORKDIR /app

# Cache de dependencias: copiamos pubspec primero para reaprovechar capas.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copia el resto del proyecto.
COPY . .

# Fail-fast si Coolify olvidó setear los build args. Sin esto el `.env`
# quedaría con valores vacíos y la app fallaría en runtime con un error
# poco descriptivo de "Invalid URL".
RUN test -n "${SUPABASE_URL}" \
    || (echo "ERROR: SUPABASE_URL build arg vacío. Configurar en Coolify." >&2 && exit 1)
RUN test -n "${SUPABASE_ANON_KEY}" \
    || (echo "ERROR: SUPABASE_ANON_KEY build arg vacío. Configurar en Coolify." >&2 && exit 1)

# Escribe el .env con los build args. flutter_dotenv lo lee del bundle.
RUN echo "SUPABASE_URL=${SUPABASE_URL}"           > .env \
 && echo "SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}" >> .env

# Build web. CanvasKit para mejor fidelidad visual (defecto en stable).
RUN flutter build web --release --base-href / --no-tree-shake-icons

# ============================================================================
# Runtime stage — nginx sirviendo build/web.
# ============================================================================
FROM nginx:alpine AS runtime

# Reemplaza la config por defecto con la nuestra (SPA + cache headers).
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copia el build de Flutter al docroot.
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80

# Healthcheck simple — Coolify lo lee.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
