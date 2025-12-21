require 'spec_helper'

RSpec.describe User do
  describe '#initialize' do
    context 'with a name' do
      let(:name) { 'Alice' }
      let(:user) { described_class.new(name) }

      it 'sets @name instance variable' do
        expect(user.instance_variable_get(:@name)).to eq(name)
      end
    end

    context 'with nil name' do
      let(:user) { described_class.new(nil) }

      it 'allows nil name' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end
  end

  describe '#find_user' do
    let(:user) { described_class.new('anything') }
    let(:db) { double('DB') }

    before do
      stub_const('DB', db)
    end

    context 'with integer id' do
      let(:id) { 42 }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'executes the expected SQL against DB and returns the result' do
        result = [{ 'id' => 42, 'name' => 'Bob' }]
        expect(db).to receive(:execute).with(expected_query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with string id' do
      let(:id) { '123' }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'interpolates the id as-is into the SQL' do
        expect(db).to receive(:execute).with(expected_query).and_return(['ok'])
        expect(user.find_user(id)).to eq(['ok'])
      end
    end

    context 'with nil id' do
      let(:id) { nil }
      let(:expected_query) { "SELECT * FROM users WHERE id = " }

      it 'builds a query with an empty id and calls DB' do
        expect(db).to receive(:execute).with(expected_query).and_return([])
        expect(user.find_user(id)).to eq([])
      end
    end

    context 'with potentially dangerous id input' do
      let(:id) { "1; DROP TABLE users; --" }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'passes the raw interpolated SQL to DB' do
        expect(db).to receive(:execute).with(expected_query).and_return('done')
        expect(user.find_user(id)).to eq('done')
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 5 }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'propagates the error' do
        expect(db).to receive(:execute).with(expected_query).and_raise(StandardError, 'DB failure')
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'DB failure')
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('any') }

    it 'returns the sum of 1, 2, and 3' do
      expect(user.bad_method).to eq(6)
    end

    it 'does not raise an error' do
      expect do
        user.bad_method
      end.not_to raise_error
    end
  end
end
