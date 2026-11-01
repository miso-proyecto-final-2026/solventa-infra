// Comportamiento por defecto: la consola web tiene un build por idioma (/es-CO/ y /en-US/). Sin idioma, lleva al base;
// una ruta de la aplicación (sin extensión) sirve el index.html de su idioma y el enrutador de Angular hace el resto.
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  var match = uri.match(/^\/(es-CO|en-US)(\/.*)?$/);

  if (!match) {
    return {
      statusCode: 302,
      statusDescription: 'Found',
      headers: { location: { value: '/es-CO' + (uri === '/' ? '/' : uri) } },
    };
  }

  var last = uri.substring(uri.lastIndexOf('/') + 1);
  if (last.indexOf('.') === -1) {
    request.uri = '/' + match[1] + '/index.html';
  }
  return request;
}
