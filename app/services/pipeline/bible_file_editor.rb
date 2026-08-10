require "fileutils"

# ---------------------------------------------------------------------------
# Pipeline::BibleFileEditor
#
# The sole code path in the app that touches File, flock, or .tmp-then-rename
# for any bible file. Mechanics only — no bible-domain knowledge (no
# reference to characters, terminology, cards, or headings). Built for R6's
# preread writer and R5's BibleReviewWriter to share, so every hardening
# measure lives in exactly one place rather than being reinvented per
# writer; only BibleReviewWriter remains as of docs/PREREAD_STAGING_DESIGN.md's
# Group D, which retired the preread writer this was originally built
# alongside — kept regardless, since BibleReviewWriter still depends on it.
# See docs/RAILS_REFACTOR_PLAN.md's R6 section.
#
# Locking uses a dedicated sidecar "<file>.lock" path that is itself never
# renamed or replaced — locking the target file's own path directly would
# be unsafe here, since a concurrent writer's already-open file descriptor
# stays pointed at the old inode after another writer's rename swaps in a
# new one, silently reading stale content. The sidecar lock file is never
# swapped, so every writer serializes on the same inode for as long as this
# file exists.
#
# Write sequence is "lock-then-revalidate": lock -> fresh read (taken *after*
# acquiring the lock, never a caller's earlier snapshot) -> caller's block
# computes the result against that fresh read -> atomic .tmp-then-rename
# write -> unlock. No retry or version-check machinery — this is a
# pessimistic critical section, not optimistic concurrency control.
#
# Only the file(s) a caller actually touches are locked, never all bible
# files preemptively; when a caller needs more than one, it is the
# caller's responsibility to acquire them in canonical filename order.
# ---------------------------------------------------------------------------
module Pipeline
  class BibleFileEditor
    # Sentinel a #append_block caller's block returns to mean "nothing to
    # write" — distinct from any real content, including an empty string.
    SKIP = :no_change

    # Lock -> fresh read -> count exact occurrences of `current` in the fresh
    # content -> exactly one: atomic write with `proposed` substituted,
    # return :applied; zero: :skipped_not_found; more than one:
    # :skipped_ambiguous. Purely mechanical text matching, no domain logic.
    def replace(file, current:, proposed:)
      with_lock(file) do
        fresh = read(file)
        case fresh.scan(current).length
        when 0 then :skipped_not_found
        when 1
          # Block form avoids String#sub's special \1/\& backreference
          # interpretation of the replacement argument — `proposed` is
          # substituted as literal text, never as a backreference template.
          write_atomic(file, fresh.sub(current) { proposed })
          :applied
        else
          :skipped_ambiguous
        end
      end
    end

    # Lock -> fresh read -> yield the freshly-read content to the caller's
    # block. The block owns all domain logic (dedup, merging, whatever "new"
    # means for its caller) and returns either the full content to write, or
    # SKIP to mean nothing changed. The write only happens if told to.
    def append_block(file, &block)
      with_lock(file) do
        fresh = read(file)
        result = block.call(fresh)
        next SKIP if result == SKIP

        write_atomic(file, result)
        :applied
      end
    end

    private

    def read(file)
      File.exist?(file) ? File.read(file, encoding: "UTF-8") : ""
    end

    def with_lock(file)
      FileUtils.mkdir_p(File.dirname(file))
      lock_path = "#{file}.lock"
      File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      end
    end

    def write_atomic(file, content)
      tmp_path = "#{file}.tmp"
      File.write(tmp_path, content, encoding: "UTF-8")
      File.rename(tmp_path, file)
    end
  end
end
