// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Auto password toggle — applied to every input[type=password] on any page
function initPasswordToggles() {
  document.querySelectorAll('input[type="password"]:not([data-pw-toggle])').forEach(function(input) {
    input.setAttribute('data-pw-toggle', '1');

    var wrapper = document.createElement('div');
    wrapper.style.cssText = 'position:relative;display:block;';

    input.parentNode.insertBefore(wrapper, input);
    wrapper.appendChild(input);

    var btn = document.createElement('button');
    btn.type = 'button';
    btn.setAttribute('aria-label', 'Hiện/Ẩn mật khẩu');
    btn.style.cssText = 'position:absolute;right:12px;top:50%;transform:translateY(-50%);background:none;border:none;cursor:pointer;padding:4px;display:flex;align-items:center;justify-content:center;color:#94a3b8;transition:color .15s;z-index:10;';
    btn.innerHTML = eyeIcon();

    btn.addEventListener('mouseenter', function() { btn.style.color = '#64748b'; });
    btn.addEventListener('mouseleave', function() { btn.style.color = '#94a3b8'; });

    btn.addEventListener('click', function() {
      var shown = input.type === 'text';
      input.type = shown ? 'password' : 'text';
      btn.innerHTML = shown ? eyeIcon() : eyeOffIcon();
      btn.style.color = shown ? '#94a3b8' : '#6366f1';
    });

    wrapper.appendChild(btn);

    // Add right padding so text doesn't go under the button
    var computed = window.getComputedStyle(input);
    var existingPR = parseInt(computed.paddingRight) || 0;
    if (existingPR < 40) input.style.paddingRight = '40px';
  });
}

function eyeIcon() {
  return '<svg width="18" height="18" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>';
}

function eyeOffIcon() {
  return '<svg width="18" height="18" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19m-6.72-1.07a3 3 0 11-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>';
}

document.addEventListener('DOMContentLoaded', initPasswordToggles);
document.addEventListener('turbo:load', initPasswordToggles);
document.addEventListener('turbo:render', initPasswordToggles);
