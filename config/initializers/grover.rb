# Use system Chromium instead of puppeteer's bundled Chrome
# Avoids missing shared library errors on the server (libatk-1.0.so.0 etc.)
Grover.configure do |config|
  system_chrome = %w[
    /usr/bin/chromium-browser
    /usr/bin/chromium
    /snap/bin/chromium
    /usr/bin/google-chrome
    /usr/bin/google-chrome-stable
  ].find { |p| File.executable?(p) }

  config.options = {
    executable_path: system_chrome,
    args: %w[
      --no-sandbox
      --disable-setuid-sandbox
      --disable-dev-shm-usage
      --disable-gpu
      --disable-software-rasterizer
      --no-first-run
      --no-zygote
      --single-process
    ]
  }
end
