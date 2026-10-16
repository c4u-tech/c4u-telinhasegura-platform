import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// Credentials on: the browser attaches the HttpOnly session cookie to the
/// API's origin. Not unit-tested: it needs a browser.
http.Client createHttpClient() => BrowserClient()..withCredentials = true;
