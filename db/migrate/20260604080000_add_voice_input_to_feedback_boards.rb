class AddVoiceInputToFeedbackBoards < ActiveRecord::Migration[7.2]
  def change
    # Allow admin to enable voice-to-text input on the participant feedback form.
    # Requires workspace to have :stt feature (Pro+ plan).
    add_column :feedback_boards, :allow_voice_input, :boolean, default: false, null: false
  end
end
