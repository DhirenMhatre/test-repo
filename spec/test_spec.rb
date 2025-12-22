require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a String name' do
      let(:name) { 'Alice' }

      it 'stores the name in @name' do
        user = described_class.new(name)
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with a non-String name' do
      let(:name) { 123 }

      it 'stores the object as-is in @name' do
        user = described_class.new(name)
        expect(user.instance_variable_get(:@name)).to eq(123)
      end
    end

    context 'with nil name' do
      let(:name) { nil }

      it 'stores nil in @name' do
        user = described_class.new(name)
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end
  end

  describe '#find_user' do
    let(:user) { described_class.new('any') }
    let(:db) { double('DB') }

    before do
      stub_const('DB', db)
    end

    context 'when DB executes successfully with integer id' do
      let(:id) { 42 }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }
      let(:db_result) do
        [{ id: 42, name: 'Zoe' }]
      end

      it 'calls DB.execute with the interpolated query and returns its result' do
        expect(db).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'when id is a string containing SQL-like content' do
      let(:id) { '1; DROP TABLE users; --' }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }
      let(:db_result) { :ok }

      it 'passes the raw interpolated query to DB.execute' do
        expect(db).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(:ok)
      end
    end

    context 'when id is nil' do
      let(:id) { nil }
      let(:expected_query) { 'SELECT * FROM users WHERE id = ' }
      let(:db_result) do
        []
      end

      it 'interpolates nil as empty string and calls DB.execute' do
        expect(db).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq([])
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 1 }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'propagates the error' do
        expect(db).to receive(:execute).with(expected_query).and_raise(StandardError, 'DB error')
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'DB error')
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('any') }

    it 'returns 6' do
      expect(user.bad_method).to eq(6)
    end

    it 'returns an Integer' do
      expect(user.bad_method).to be_a(Integer)
    end

    it 'raises ArgumentError when given unexpected arguments' do
      expect do
        user.bad_method(1)
      end.to raise_error(ArgumentError)
    end
  end
end
