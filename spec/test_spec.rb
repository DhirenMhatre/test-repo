require 'spec_helper'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name' do
      let(:name) { 'Alice' }

      it 'sets @name to the provided value' do
        user = described_class.new(name)
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with an empty string name' do
      let(:name) { '' }

      it 'sets @name to empty string' do
        user = described_class.new(name)
        expect(user.instance_variable_get(:@name)).to eq('')
      end
    end

    context 'with nil name' do
      let(:name) { nil }

      it 'sets @name to nil' do
        user = described_class.new(name)
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end
  end

  describe '#find_user' do
    let(:user) { described_class.new('Tester') }
    let(:db_double) { double('DB') }

    before do
      stub_const('DB', db_double)
    end

    context 'when DB.execute succeeds with integer id' do
      let(:id) { 42 }
      let(:db_result) do
        [{ id: 42, name: 'Bob' }]
      end

      it 'calls DB.execute with the constructed SQL and returns the result' do
        expect(db_double).to receive(:execute).with('SELECT * FROM users WHERE id = 42').and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'when DB.execute succeeds with string id' do
      let(:id) { '7' }
      let(:db_result) do
        [{ id: 7, name: 'Eve' }]
      end

      it 'interpolates the string id and returns the DB result' do
        expect(db_double).to receive(:execute).with('SELECT * FROM users WHERE id = 7').and_return(db_result)
        expect(user.find_user(id)).to eq(db_result)
      end
    end

    context 'when id is nil' do
      let(:id) { nil }
      let(:db_result) do
        []
      end

      it 'passes an incomplete SQL statement to DB.execute and returns the DB result' do
        expect(db_double).to receive(:execute).with('SELECT * FROM users WHERE id = ').and_return(db_result)
        expect(user.find_user(id)).to eq(db_result)
      end
    end

    context 'when id contains special characters (possible injection)' do
      let(:id) { '1; DROP TABLE users; --' }
      let(:db_result) do
        []
      end

      it 'interpolates the raw id into the SQL and returns the DB result' do
        expect(db_double).to receive(:execute).with('SELECT * FROM users WHERE id = 1; DROP TABLE users; --').and_return(db_result)
        expect(user.find_user(id)).to eq(db_result)
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 5 }
      let(:error) { StandardError.new('DB failure') }

      it 'propagates the error' do
        expect(db_double).to receive(:execute).with('SELECT * FROM users WHERE id = 5').and_raise(error)
        expect do
          user.find_user(id)
        end.to raise_error(error.class, 'DB failure')
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('Tester') }

    it 'returns the sum of x, y, and z' do
      expect(user.bad_method).to eq(6)
    end

    it 'does not modify instance variables' do
      user.instance_variable_set(:@name, 'Original')
      expect(user.bad_method).to eq(6)
      expect(user.instance_variable_get(:@name)).to eq('Original')
    end
  end
end
