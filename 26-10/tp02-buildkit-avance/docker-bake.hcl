variable "VERSION" {
  default = "dev"
}

variable "GIT_SHA" {
  default = "local"
}

variable "REGISTRY" {
  default = "localhost:5000"
}

group "default" {
  targets = ["api", "worker"]
}

# Labels, plateformes et cache partagés.
# Cache local pour que `bake --load` marche sans le registre du TP03.
# En CI : type=registry,ref=${REGISTRY}/cache:<cible>,mode=max
#         ou type=gha / type=s3. Voir RAPPORT.md.
target "_common" {
  platforms = ["linux/amd64", "linux/arm64"]
  args = {
    APP_VERSION = "${VERSION}"
    GIT_SHA     = "${GIT_SHA}"
  }
  labels = {
    "org.opencontainers.image.version"  = "${VERSION}"
    "org.opencontainers.image.revision" = "${GIT_SHA}"
  }
  cache-from = ["type=local,src=tmp/bake-cache"]
  cache-to   = ["type=local,dest=tmp/bake-cache,mode=max"]
}

target "api" {
  inherits   = ["_common"]
  context    = "../tp01-optimisation-image/starter/shopapi"
  dockerfile = "Dockerfile"
  tags       = ["${REGISTRY}/shopapi:${VERSION}"]
}

target "worker" {
  inherits   = ["_common"]
  context    = "starter/shop-worker"
  dockerfile = "Dockerfile"
  tags       = ["${REGISTRY}/shop-worker:${VERSION}"]
  secret     = ["id=pipconf,src=starter/shop-worker/pip.conf"]
}

# Uniquement le stage test, sur l'architecture de la machine.
target "worker-test" {
  context    = "starter/shop-worker"
  dockerfile = "Dockerfile"
  target     = "test"
  secret     = ["id=pipconf,src=starter/shop-worker/pip.conf"]
  args = {
    APP_VERSION = "${VERSION}"
    GIT_SHA     = "${GIT_SHA}"
  }
  tags   = ["shop-worker:test"]
  output = ["type=docker"]
}
