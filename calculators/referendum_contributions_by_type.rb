class ReferendumContributionsByType
  TYPE_DESCRIPTIONS = {
    'IND' => 'Individual',
    'COM' => 'Committee',
    'OTH' => 'Other (includes Businesses)',
    'SLF' => 'Self Funding'
  }

  def initialize(candidates: [], ballot_measures: [], committees: [])
    @ballot_measures = ballot_measures
    @committees_by_filer_id =
      committees.where('"Filer_ID" IS NOT NULL').index_by { |c| c.Filer_ID }
  end

  def fetch
    contributions = ActiveRecord::Base.connection.execute(<<-SQL)
      WITH contributions_by_type AS (
        SELECT "Filer_ID",
        CASE
          WHEN "Entity_Cd" = 'SCC' THEN 'COM'
          ELSE "Entity_Cd"
        END AS type,
        SUM("Tran_Amt1") AS total
        FROM combined_contributions
        GROUP BY "Filer_ID", type
      )
      SELECT
        "Ballot_Measure" AS "Measure_Number",
        "Support_Or_Oppose" AS "Sup_Opp_Cd",
        contributions_by_type.type,
        SUM(contributions_by_type.total) as total
      FROM contributions_by_type
      INNER JOIN oakland_committees committees
        ON committees."Filer_ID" = contributions_by_type."Filer_ID"
      GROUP BY "Ballot_Measure", "Support_Or_Oppose", contributions_by_type.type
      ORDER BY "Ballot_Measure", "Support_Or_Oppose", contributions_by_type.type;
    SQL

    support = {}
    oppose = {}

    contributions.each do |row|
      measure = row['Measure_Number']
      if measure.nil?
        puts 'WARN empty measure number: ' + row.inspect
        next
      end
      if row['Sup_Opp_Cd'] == 'S'
        support[measure] ||= {}
        support[measure][TYPE_DESCRIPTIONS[row['type']]] = row['total']
      elsif row['Sup_Opp_Cd'] == 'O'
        oppose[measure] ||= {}
        oppose[measure][TYPE_DESCRIPTIONS[row['type']]] = row['total']
      end
    end

    [
      [support, :supporting_type],
      [oppose, :opposing_type],
    ].each do |by_type, calculation_name|
      by_type.keys.map do |measure|
        ballot_measure = ballot_measure_from_number(measure)
        result = by_type[measure].keys.map do |type|
          amount = by_type[measure][type]
          {
            type: type,
            amount: amount,
          }
        end
        ballot_measure.save_calculation(calculation_name, result)
      end
    end
  end
  def ballot_measure_from_number(bal_number)
    @ballot_measures.detect do |measure|
      measure['Measure_number'] == bal_number
    end
  end
end
