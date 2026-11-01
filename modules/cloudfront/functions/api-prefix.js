// Comportamiento /api/*: replica el pathRewrite de proxy.conf.json de solventa-web. La consola llama a
// /api/<servicio>/v1/...; el API Gateway enruta por /v1/... Lo que no tenga esa forma no se reescribe y termina en 404.
function handler(event) {
  var request = event.request;
  request.uri = request.uri.replace(/^\/api\/[^/]+(\/v1\/.*)$/, '$1');
  return request;
}
