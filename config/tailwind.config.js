const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
  content: [
    './public/*.html',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/views/**/*.{erb,haml,html,slim}'
  ],
  theme: {
    extend: {
      fontFamily: {
        inter: ['Inter', ...defaultTheme.fontFamily.sans],
      },
      colors: {
        indigo: {
          50:  '#f0f3f9',
          100: '#dde4ef',
          200: '#bcc9de',
          400: '#4a6080',
          500: '#243550',
          600: '#0f172a',
          700: '#090f1c',
        },
        violet: {
          50:  '#f0f3f9',
          100: '#dde4ef',
          200: '#bcc9de',
          400: '#4a6080',
          500: '#243550',
          600: '#0f172a',
          700: '#090f1c',
        }
      }
    },
  },
  plugins: [],
}
