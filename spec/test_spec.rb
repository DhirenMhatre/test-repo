require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a String name' do
      let(:name) do
        'Alice'
      end

      let(:user) do
        described_class.new(name)
      end

      it 'sets the @name instance variable to the provided string' do
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

    context 'with a non-String name' do
      let(:name) do
        123
      end

      let(:user) do
        described_class.new(name)
      end

      it 'stores the value as-is' do
        expect(user.instance_variable_get(:@name)).to eq(123)
      end
    end
  end

  describe '#find_user' do
    let(:user) do
      described_class.new('Bob')
    end

    let(:db) do
      instance_double('DB')
    end

    before do
      stub_const('DB', db)
    end

    context 'with an Integer id' do
      let(:id) do
        42
      end

      let(:result) do
        [{ 'id' => 42, 'name' => 'Bob' }]
      end

      it 'calls DB.execute with the expected SQL and returns the DB result' do
        expect(db).to receive(:execute).with('SELECT * FROM users WHERE id = 42').and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a String id (potentially unsafe input)' do
      let(:id) do
        '1 OR 1=1'
      end

      let(:result) do
        [{ 'id' => 1, 'name' => 'Alice' }, { 'id' => 2, 'name' => 'Eve' }]
      end

      it 'interpolates the string into the SQL and returns the DB result' do
        expect(db).to receive(:execute).with('SELECT * FROM users WHERE id = 1 OR 1=1').and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with nil id' do
      let(:id) do
        nil
      end

      let(:result) do
        []
      end

      it 'produces a SQL statement with an empty interpolation for nil and returns the DB result' do
        expect(db).to receive(:execute).with('SELECT * FROM users WHERE id = ').and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'when DB.execute raises an error' do
      it 'propagates the error' do
        allow(db).to receive(:execute).and_raise(StandardError, 'DB error')
        expect do
          user.find_user(7)
        end.to raise_error(StandardError, 'DB error')
      end
    end
  end

  describe '#bad_method' do
    let(:user) do
      described_class.new('Charlie')
    end

    it 'returns the sum of internal variables (6)' do
      expect(user.bad_method).to eq(6)
    end

    it 'does not depend on @name value' do
      other_user = described_class.new(nil)
      expect(other_user.bad_method).to eq(6)
    end

    it 'raises ArgumentError when called with unexpected arguments' do
      expect do
        user.bad_method(1)
      end.to raise_error(ArgumentError)
    end
  end
end
