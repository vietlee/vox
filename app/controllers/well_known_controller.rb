# Serves the platform association files that let iOS Universal Links and
# Android App Links open the native VOX Learner app instead of the PWA when
# a learner taps an https://vox.czin.net link (e.g. an invite email).
#
# Both files MUST be served over HTTPS, as application/json, with no redirect.
class WellKnownController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :set_current_workspace

  # iOS bundle id + Apple Team ID (Runner target).
  IOS_APP_ID = "K85T59A85W.com.vox.voxLearner".freeze

  # Android application id + SHA256 signing fingerprint(s).
  # NOTE: fingerprints must match the certificate that signs the *shipped* APK.
  # The current build.gradle signs release with the debug keystore, whose
  # fingerprint is listed below. When you move to a real upload/release key
  # (and/or Play App Signing), add that certificate's SHA256 here too.
  ANDROID_PACKAGE = "com.vox.learner".freeze
  ANDROID_SHA256_FINGERPRINTS = [
    "69:DE:94:2D:97:E8:8B:AD:F0:3C:4B:9D:BB:C4:57:93:E3:7F:41:BC:0A:3F:18:50:A5:82:75:E2:C7:BD:0B:AF"
  ].freeze

  # Paths that should open the native app when tapped from an email / shared
  # link. Every entry has a matching in-app route in the Flutter app; anything
  # not listed keeps opening the PWA in the browser.
  APP_LINK_PATHS = [
    "/learn/invite/*",                       # teacher invites a learner
    "/invite/*",                             # learner invites a friend (referral)
    "/learner",                              # daily-reminder → dashboard/home
    "/learner/quiz_assignments/*",           # assigned quiz
    "/learner/flashcard_assignments/*",      # assigned flashcard deck
    "/learner/learning_path_assignments/*"   # assigned learning path
  ].freeze

  def apple_app_site_association
    render json: {
      applinks: {
        details: [
          {
            appIDs: [IOS_APP_ID],
            components: APP_LINK_PATHS.map { |p| { "/" => p } }
          }
        ]
      }
    }
  end

  def assetlinks
    render json: [
      {
        relation: ["delegate_permission/common.handle_all_urls"],
        target: {
          namespace: "android_app",
          package_name: ANDROID_PACKAGE,
          sha256_cert_fingerprints: ANDROID_SHA256_FINGERPRINTS
        }
      }
    ]
  end
end
