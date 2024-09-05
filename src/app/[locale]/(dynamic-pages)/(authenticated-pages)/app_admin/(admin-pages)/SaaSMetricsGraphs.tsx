'use client';
import { GraphContainer } from '@/components/GraphContainer';
import { MRRBarListChart } from './_graphs/MRRBarListChart';
const valueFormatter = (number: number) =>
  `$ ${Intl.NumberFormat('us').format(number).toString()}`;

const mrrDonutListData = [
  {
    name: 'MRR',
    value: 120,
    fill: "hsl(var(--chart-1))"
  },
  {
    name: 'ARR',
    value: 157,
    fill: "hsl(var(--chart-4))"
  },
  {
    name: 'ARPU',
    value: 109,
    fill: "hsl(var(--chart-3))"
  },
  {
    name: 'LTV',
    value: 99,
    fill: "hsl(var(--chart-2))"
  },
  {
    name: 'CAC',
    value: 132,
    fill: "hsl(var(--chart-5))"
  },
];

export function SaaSMetricsGraphs({
  churnRateData,
  mrrData,
  organizationCountByMonth,
  projectCountByMonth,
  userCountByMonth,
}: {
  churnRateData: Array<{
    month: string;
    churnRate: string;
  }>;
  mrrData: Array<{
    month: string;
    mrr: string;
  }>;
  organizationCountByMonth: Array<{
    month: string;
    number_of_organizations: number;
  }>;
  projectCountByMonth: Array<{
    month: string;
    number_of_projects: number;
  }>;
  userCountByMonth: Array<{
    month: string;
    number_of_users: number;
  }>;
}) {
  return (
    <div className="flex flex-col space-y-2 mt-12 ">
      <p className="text-2xl font-bold mb-2">Admin Analytics</p>
      <div className="grid grid-cols-1 md:grid-cols-2 grid-flow-row auto-rows-max w-full gap-10 ">
        <GraphContainer
          title="Monthly Churn Rate"
          subTitle="Monthly recurring revenue"
        >
          <MRRBarListChart />
        </GraphContainer>
        <GraphContainer
          title="MRR Analytics"
          subTitle="Monthly churn rate vs Organization Count"
        >
          <MRRBarListChart />
        </GraphContainer>
      </div>

      <div>
        <p className="text-2xl mt-10 mb-2 font-bold">All Stats</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 grid-flow-row auto-rows-max gap-10">
        <GraphContainer
          title="Organizations by month"
          subTitle="Number of organizations"
        >
          <MRRBarListChart />
        </GraphContainer>
        <GraphContainer title="Projects by Month" subTitle="Number of projects">
          <MRRBarListChart />
        </GraphContainer>
        <GraphContainer title="User by month" subTitle="Number of users">
          <MRRBarListChart />
        </GraphContainer>
      </div>
    </div>
  );
}
