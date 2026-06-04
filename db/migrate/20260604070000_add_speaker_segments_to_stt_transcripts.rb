class AddSpeakerSegmentsToSttTranscripts < ActiveRecord::Migration[7.2]
  def change
    # Stores pre-processed speaker segments for diarized transcripts.
    # Format: [{ speaker_id:, start:, end:, tokens: [] }, ...]
    # Null means no diarization was requested / no speaker data available.
    add_column :stt_transcripts, :speaker_segments, :jsonb, default: nil
  end
end
