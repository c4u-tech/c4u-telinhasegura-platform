/// The sandbox of the frame that holds the kid player on the web. It lets
/// the YouTube embed run its scripts and keep its own origin (it does not
/// play without them) and leaves out every token that opens a way out:
/// without `allow-popups` (and `allow-popups-to-escape-sandbox`) the
/// YouTube logo, the video title and end-screen links cannot open a new
/// tab, and without `allow-top-navigation` (in any form) they cannot
/// replace the app's page with youtube.com. `allow-same-origin` must stay,
/// since without it YouTube does not play; it is safe because the framed
/// document is the player package's own page, and the cross-origin YouTube
/// frame inside it inherits these flags but still cannot touch the app.
/// On mobile the WebView's
/// navigation rules close the same doors.
const kKidFrameSandbox = 'allow-scripts allow-same-origin';
