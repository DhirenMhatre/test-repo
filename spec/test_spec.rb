require 'spec_helper'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name' do
      let(:name) { 'Alice' }
      let(:user) { described_class.new(name) }

      it 'sets the @name instance variable' do
        expect(user.instance_variable_get(:@name)).to eq(name)
      end
    end

    context 'with nil name' do
      let(:name) { nil }
      let(:user) { described_class.new(name) }

      it 'sets the @name instance variable to nil' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'with empty string name' do
      let(:name) { '' }
      let(:user) { described_class.new(name) }

      it 'sets the @name instance variable to empty string' do
        expect(user.instance_variable_get(:@name)).to eq('')
      end
    end
  end

  describe '#find_user' do
    let(:user) { described_class.new('Alice') }
    let(:db_double) { double('DB') }

    before do
      stub_const('DB', db_double)
    end

    context 'when DB.execute succeeds' do
      it 'executes the correct SQL with integer id and returns the result' do
        id = 42
        expected_query = 'SELECT * FROM users WHERE id = 42'
        expected_result = { id: 42, name: 'Alice' }
        expect(db_double).to receive(:execute).with(expected_query).and_return(expected_result)
        result = user.find_user(id)
        expect(result).to eq(expected_result)
      end

      it 'passes through a string id even if it looks unsafe' do
        id = '1; DROP TABLE users'
        expected_query = 'SELECT * FROM users WHERE id = 1; DROP TABLE users'
        expected_result = :ok
        expect(db_double).to receive(:execute).with(expected_query).and_return(expected_result)
        result = user.find_user(id)
        expect(result).to eq(expected_result)
      end

      it 'handles nil id by interpolating to an empty string' do
        id = nil
        expected_query = 'SELECT * FROM users WHERE id = '
        expected_result = nil
        expect(db_double).to receive(:execute).with(expected_query).and_return(expected_result)
        result = user.find_user(id)
        expect(result).to be_nil
      end

      it 'returns nil when DB returns nil' do
        id = 7
        expected_query = 'SELECT * FROM users WHERE id = 7'
        expect(db_double).to receive(:execute).with(expected_query).and_return(nil)
        result = user.find_user(id)
        expect(result).to be_nil
      end
    end

    context 'when DB.execute raises an error' do
      it 'propagates the error' do
        id = 5
        expected_query = 'SELECT * FROM users WHERE id = 5'
        expect(db_double).to receive(:execute).with(expected_query).and_raise(StandardError, 'boom')
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'boom')
      end
    end
  end

  describe '#bad_method' do
    context 'for any user' do
      let(:user) { described_class.new('Bob') }

      it 'returns the constant sum 6' do
        expect(user.bad_method).to eq(6)
      end

      it 'returns an Integer' do
        expect(user.bad_method).to be_a(Integer)
      end
    end

    context 'when name is nil' do
      let(:user) { described_class.new(nil) }

      it 'still returns 6' do
        expect(user.bad_method).to eq(6)
      end
    end
  end
end
