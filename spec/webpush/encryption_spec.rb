require 'spec_helper'

describe Webpush::Encryption do
  describe '#encrypt' do
    let(:curve) do
      group = 'prime256v1'
      curve = OpenSSL::PKey::EC.new(group)
      curve.generate_key
      curve
    end

    let(:p256dh) do
      ecdh_key = curve.public_key.to_bn.to_s(2)
      encode64(ecdh_key)
    end

    let(:auth) { encode64(Random.new.bytes(16)) }

    it 'returns ECDH encrypted cipher text, salt, and server_public_key' do
      payload = Webpush::Encryption.encrypt('Hello World', p256dh, auth)

      payload_vals = extract_payload_values(payload)

      decrypted_data = Webpush::Encryption.decrypt(payload_vals[:ciphertext],
                                   key: payload_vals[:shared_secret],
                                   salt: payload_vals[:salt],
                                   server_public_key_bn: payload_vals[:server_public_key_bn],
                                   p256dh: p256dh,
                                   auth: auth)

      expect(decrypted_data).to eq('Hello World')
    end

    it 'returns error when message is blank' do
      expect { Webpush::Encryption.encrypt(nil, p256dh, auth) }.to raise_error(ArgumentError)
      expect { Webpush::Encryption.encrypt('', p256dh, auth) }.to raise_error(ArgumentError)
    end

    it 'returns error when p256dh is blank' do
      expect { Webpush::Encryption.encrypt('Hello world', nil, auth) }.to raise_error(ArgumentError)
      expect { Webpush::Encryption.encrypt('Hello world', '', auth) }.to raise_error(ArgumentError)
    end

    it 'returns error when auth is blank' do
      expect { Webpush::Encryption.encrypt('Hello world', p256dh, '') }.to raise_error(ArgumentError)
      expect { Webpush::Encryption.encrypt('Hello world', p256dh, nil) }.to raise_error(ArgumentError)
    end

    # Bug fix for https://github.com/zaru/webpush/issues/22
    it 'handles unpadded base64 encoded subscription keys' do
      unpadded_p256dh = p256dh.gsub(/=*\Z/, '')
      unpadded_auth = auth.gsub(/=*\Z/, '')

      payload = Webpush::Encryption.encrypt('Hello World', unpadded_p256dh, unpadded_auth)

      payload_vals = extract_payload_values(payload)

      decrypted_data = Webpush::Encryption.decrypt(payload_vals[:ciphertext],
                                   key: payload_vals[:shared_secret],
                                   salt: payload_vals[:salt],
                                   server_public_key_bn: payload_vals[:server_public_key_bn],
                                   p256dh: unpadded_p256dh,
                                   auth: unpadded_auth)

      expect(decrypted_data).to eq('Hello World')
    end

    def extract_payload_values payload
      salt = payload.byteslice(0, 16)
      rs = payload.byteslice(16, 4).unpack("N*").first
      idlen = payload.byteslice(20).unpack("C*").first
      serverkey16bn = payload.byteslice(21, idlen)
      ciphertext = payload.byteslice(21 + idlen, rs)

      expect(payload.bytesize).to eq(21 + idlen + rs)

      group_name = 'prime256v1'
      group = OpenSSL::PKey::EC::Group.new(group_name)
      server_public_key_bn = OpenSSL::BN.new(serverkey16bn.unpack('H*').first, 16)
      server_public_key = OpenSSL::PKey::EC::Point.new(group, server_public_key_bn)
      shared_secret = curve.dh_compute_key(server_public_key)

      {
          ciphertext: ciphertext,
          shared_secret: shared_secret,
          salt: salt,
          server_public_key_bn: server_public_key_bn
      }
    end

    def encode64(bytes)
      Base64.urlsafe_encode64(bytes)
    end

    def decode64(str)
      Base64.urlsafe_decode64(str)
    end

    def pad64(str)
      str = str.ljust((str.length + 3) & ~3, '=') if !str.end_with?('=') && str.length % 4 != 0
      str
    end
  end
end
