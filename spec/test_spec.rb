require 'spec_helper'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name' do
      let(:name) do
        'Alice'
      end

      let(:user) do
        described_class.new(name)
      end

      it 'creates a User instance' do
        expect(user).to be_a(described_class)
      end

      it 'sets the @name instance variable' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      let(:name) do
        nil
      end

      let(:user) do
        described_class.new(name)
      end

      it 'sets @name to nil' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'without arguments' do
      it 'raises ArgumentError' do
        expect do
          described_class.new
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe '#find_user' do
    let(:name) do
      'Alice'
    end

    let(:user) do
      described_class.new(name)
    end

    let(:db_double) do
      double('DB')
    end

    before do
      stub_const('DB', db_double)
    end

    context 'with integer id' do
      let(:id) do
        42
      end

      let(:expected_query) do
        'SELECT * FROM users WHERE id = 42'
      end

      it 'calls DB.execute with the expected SQL and returns the result' do
        result = [{ id: 42, name: 'Alice' }]
        allow(DB).to receive(:execute).with(expected_query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with string id' do
      let(:id) do
        '7'
      end

      let(:expected_query) do
        'SELECT * FROM users WHERE id = 7'
      end

      it 'interpolates the string into the SQL' do
        allow(DB).to receive(:execute).with(expected_query).and_return('ok')
        expect(user.find_user(id)).to eq('ok')
      end
    end

    context 'with nil id' do
      let(:expected_query) do
        'SELECT * FROM users WHERE id = '
      end

      it 'interpolates empty string for nil and returns nil when DB returns nil' do
        allow(DB).to receive(:execute).with(expected_query).and_return(nil)
        expect(user.find_user(nil)).to be_nil
      end
    end

    context 'when DB.execute raises an error' do
      it 'propagates the error' do
        allow(DB).to receive(:execute).and_raise(StandardError, 'db failure')
        expect do
          user.find_user(1)
        end.to raise_error(StandardError, 'db failure')
      end
    end

    context 'with a potentially unsafe id' do
      let(:id) do
        '1; DROP TABLE users; --'
      end

      let(:expected_query) do
        'SELECT * FROM users WHERE id = 1; DROP TABLE users; --'
      end

      it 'passes the unsanitized SQL to DB.execute as-is' do
        allow(DB).to receive(:execute).with(expected_query).and_return(:danger)
        expect(user.find_user(id)).to eq(:danger)
      end
    end
  end

  describe '#bad_method' do
    let(:user) do
      described_class.new('Bob')
    end

    it 'returns the sum of x, y, and z' do
      expect(user.bad_method).to eq(6)
    end

    it 'does not raise an error' do
      expect do
        user.bad_method
      end.not_to raise_error
    end
  end
end
