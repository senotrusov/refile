require "redis"

module Refile
  class File
    # @return [Backend] the backend the file is stored in
    attr_reader :backend

    # @return [String] the id of the file
    attr_reader :id

    # @api private
    def initialize(backend, id)
      @backend = backend
      @id = id
    end

    # Reads from the file.
    #
    # @see http://www.ruby-doc.org/core-2.2.0/IO.html#method-i-read
    #
    # @return [String] The contents of the read chunk
    def read(*args)
      io.read(*args)
    end

    # Returns whether there is more data to read. Returns true if the end of
    # the data has been reached.
    #
    # @return [Boolean]
    def eof?
      io.eof?
    end

    # Close the file object and release its file descriptor.
    #
    # @return [void]
    def close
      io.close
    end

    # @return [Integer] the size of the file in bytes
    def size
      cache_key = ::Refile.backend_cache_path / @id
      if ::File.exist?(cache_key)
        ::File.size(cache_key) rescue backend.size(id)
      else
        backend.size(id)
      end
    end

    # Remove the file from the backend.
    #
    # @return [void]
    def delete
      backend.delete(id)
    end

    # @return [Boolean] whether the file exists in the backend
    def exists?
      backend.exists?(id)
    end

    # @return [IO] an IO object which contains the contents of the file
    def to_io
      io
    end

    # Downloads the file to a Tempfile on disk and returns this tempfile.
    #
    # @example
    #   file = backend.upload(StringIO.new("hello"))
    #   tempfile = file.download
    #   File.read(tempfile.path) # => "hello"
    #
    # @return [Tempfile] a tempfile with the file's content
    def download
      return io if io.is_a?(Tempfile)

      Tempfile.new(id, binmode: true).tap do |tempfile|
        IO.copy_stream(io, tempfile)
        tempfile.rewind
        tempfile.fsync
      end
    end

    # Rewind to beginning of file.
    #
    # @return [nil]
    def rewind
      @io = nil
    end

    # Prevent from exposing secure information unexpectedly
    #
    # @return [Hash]
    def as_json
      {
        id: id,
        backend: backend.to_s
      }
    end

  private

    def io
      unless @io
        cache_key = ::Refile.backend_cache_path / @id
        if ::File.exist?(cache_key)
          if (Rails.env.production? || Rails.env.staging?) && defined?(Redis)
            Redis.new.incrby("Refile.backend_cache.total_hit", (::File.size(cache_key) rescue 0)) rescue nil
          end
          @io = ::File.open(cache_key, 'r') rescue backend.open(id)
        else
          @io = backend.open(id)
          if @io.is_a?(Tempfile) && @io.respond_to?(:stat) && @io.stat.size > 0
            ::FileUtils.cp(@io.path, cache_key)
          end
        end
      end
      @io
    end
  end
end
