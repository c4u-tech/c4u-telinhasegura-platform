/// The sandbox of the frame that holds the kid player on the web. It lets
/// the YouTube embed run its scripts and keep its own origin (it does not
/// play without them) and leaves out every token that opens a way out:
/// without `allow-popups` (and `allow-popups-to-escape-sandbox`) the
/// YouTube logo, the video title and end-screen links cannot open a new
/// tab, and without `allow-top-navigation` (in any form) they cannot
/// replace the app's page with youtube.com. On mobile the WebView's
/// navigation rules close the same doors.
const kKidFrameSandbox = 'allow-scripts allow-same-origin';
