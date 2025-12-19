require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    let(:name) do
      'Alice'
    end

    let(:user) do
      described_class.new(name)
    end

    it 'creates an instance of User' do
      expect(user).to be_a(User)
    end

    it 'sets @name to the given value' do
      expect(user.instance_variable_get(:@name)).to eq('Alice')
    end

    context 'when name is nil' do
      let(:name) do
        nil
      end

      it 'sets @name to nil' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'when no name is provided' do
      it 'raises ArgumentError' do
        expect do
          described_class.new
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe '#find_user' do
    let(:user) do
      described_class.new('tester')
    end

    let(:db_double) do
      double('DB')
    end

    before do
      stub_const('DB', db_double)
    end

    context 'with an Integer id' do
      it 'calls DB.execute with the correct SQL and returns its result' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 5').and_return([{ 'id' => 5 }])
        result = user.find_user(5)
        expect(result).to eq([{ 'id' => 5 }])
      end
    end

    context 'with a String id' do
      it 'interpolates the string as-is into the SQL and returns the DB result' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = abc').and_return('ok')
        result = user.find_user('abc')
        expect(result).to eq('ok')
      end
    end

    context 'with a nil id' do
      it 'interpolates to an empty string and returns the DB result' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = ').and_return(nil)
        result = user.find_user(nil)
        expect(result).to be_nil
      end
    end

    context 'when DB.execute raises an error' do
      it 'propagates the error' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 1').and_raise(StandardError, 'boom')
        expect do
          user.find_user(1)
        end.to raise_error(StandardError, 'boom')
      end
    end

    context 'with potentially malicious input' do
      let(:payload) do
        '1; DROP TABLE users;'
      end

      it 'passes the raw input into the SQL and returns the DB result' do
        expect(DB).to receive(:execute).with("SELECT * FROM users WHERE id = #{payload}").and_return('unsafe ok')
        result = user.find_user(payload)
        expect(result).to eq('unsafe ok')
      end
    end
  end

  describe '#bad_method' do
    let(:user) do
      described_class.new('any')
    end

    it 'returns 6' do
      expect(user.bad_method).to eq(6)
    end

    context 'when @name is nil' do
      let(:user) do
        described_class.new(nil)
      end

      it 'still returns 6' do
        expect(user.bad_method).to eq(6)
      end
    end
  end
end
