require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a name string' do
      let(:name) do
        'Alice'
      end

      it 'sets @name to the provided value' do
        user = described_class.new(name)
        expect(user.instance_variable_get(:@name)).to eq(name)
      end
    end

    context 'with nil name' do
      let(:name) do
        nil
      end

      it 'sets @name to nil' do
        user = described_class.new(name)
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end
  end

  describe '#find_user' do
    let(:user) do
      described_class.new('Bob')
    end

    let(:db_double) do
      double('DB')
    end

    before do
      stub_const('DB', db_double)
    end

    context 'with integer id' do
      let(:id) do
        123
      end

      it 'executes a SELECT query with the id and returns the DB result' do
        expected_query = "SELECT * FROM users WHERE id = #{id}"
        result = [{ 'id' => 123, 'name' => 'Bob' }]
        allow(db_double).to receive(:execute).with(expected_query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with string id containing digits' do
      let(:id) do
        '456'
      end

      it 'interpolates the id directly into the query string' do
        expected_query = "SELECT * FROM users WHERE id = #{id}"
        allow(db_double).to receive(:execute).with(expected_query).and_return(:ok)
        expect(user.find_user(id)).to eq(:ok)
      end
    end

    context 'with a potentially malicious id' do
      let(:id) do
        '1 OR 1=1'
      end

      it 'passes the raw interpolated query to DB.execute' do
        expected_query = "SELECT * FROM users WHERE id = #{id}"
        allow(db_double).to receive(:execute).with(expected_query).and_return('rows')
        expect(user.find_user(id)).to eq('rows')
      end
    end

    context 'with nil id' do
      let(:id) do
        nil
      end

      it 'interpolates nil into the query and calls DB.execute' do
        expected_query = 'SELECT * FROM users WHERE id = '
        allow(db_double).to receive(:execute).with(expected_query).and_return(:nil_id_result)
        expect(user.find_user(id)).to eq(:nil_id_result)
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) do
        999
      end

      it 'propagates the error' do
        expected_query = "SELECT * FROM users WHERE id = #{id}"
        allow(db_double).to receive(:execute).with(expected_query).and_raise(StandardError, 'DB down')
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'DB down')
      end
    end
  end

  describe '#bad_method' do
    let(:user) do
      described_class.new('Eve')
    end

    it 'returns the sum of internal variables (6)' do
      expect(user.bad_method).to eq(6)
    end

    it 'returns an Integer' do
      expect(user.bad_method).to be_a(Integer)
    end
  end
end
