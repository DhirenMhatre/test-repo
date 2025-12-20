require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name' do
      let(:name) do
        'Ada'
      end

      let(:user) do
        described_class.new(name)
      end

      it 'sets the @name instance variable' do
        expect(user.instance_variable_get(:@name)).to eq('Ada')
      end
    end

    context 'with nil name' do
      let(:name) do
        nil
      end

      let(:user) do
        described_class.new(name)
      end

      it 'allows nil name and sets @name to nil' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'with empty string name' do
      let(:name) do
        ''
      end

      let(:user) do
        described_class.new(name)
      end

      it 'sets @name to empty string' do
        expect(user.instance_variable_get(:@name)).to eq('')
      end
    end
  end

  describe '#find_user' do
    let(:name) do
      'Test'
    end

    let(:user) do
      described_class.new(name)
    end

    let(:db) do
      double('DB')
    end

    before do
      stub_const('DB', db)
    end

    context 'when DB.execute succeeds with integer id' do
      let(:id) do
        42
      end

      let(:expected_query) do
        'SELECT * FROM users WHERE id = 42'
      end

      let(:result) do
        [{ 'id' => 42, 'name' => 'Zoe' }]
      end

      it 'calls DB.execute with the interpolated SQL and returns the result' do
        expect(DB).to receive(:execute).with(expected_query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'when DB.execute succeeds with string id that may be unsafe' do
      let(:id) do
        '1 OR 1=1'
      end

      let(:expected_query) do
        'SELECT * FROM users WHERE id = 1 OR 1=1'
      end

      let(:result) do
        [{ 'id' => 1, 'name' => 'Eve' }]
      end

      it 'passes the raw id into the query without sanitization and returns the result' do
        expect(DB).to receive(:execute).with(expected_query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'when id is nil' do
      let(:id) do
        nil
      end

      let(:expected_query) do
        'SELECT * FROM users WHERE id = '
      end

      it 'still calls DB.execute with a query containing nil interpolation' do
        expect(DB).to receive(:execute).with(expected_query).and_return(nil)
        expect(user.find_user(id)).to be_nil
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) do
        99
      end

      let(:expected_query) do
        'SELECT * FROM users WHERE id = 99'
      end

      it 'propagates the error' do
        expect(DB).to receive(:execute).with(expected_query).and_raise(RuntimeError, 'DB down')
        expect do
          user.find_user(id)
        end.to raise_error(RuntimeError, 'DB down')
      end
    end
  end

  describe '#bad_method' do
    let(:user) do
      described_class.new('any')
    end

    it 'returns the sum of x, y, and z' do
      expect(user.bad_method).to eq(6)
    end

    it 'does not depend on external state' do
      expect do
        user.bad_method
      end.not_to raise_error
    end
  end
end
