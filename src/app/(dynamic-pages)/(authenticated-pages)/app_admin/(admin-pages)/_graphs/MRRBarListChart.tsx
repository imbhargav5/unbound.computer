"use client"

import { TrendingUp } from "lucide-react"
import { Bar, BarChart, CartesianGrid, XAxis } from "recharts"

import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  ChartConfig,
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart"

const mrrBarListData = [
  {
    name: 'MRR',
    value: 120,

  },
  {
    name: 'ARR',
    value: 157,

  },
  {
    name: 'ARPU',
    value: 109,

  },
  {
    name: 'LTV',
    value: 99,

  },
  {
    name: 'CAC',
    value: 132,

  },
];

type MRRBarListData = {
  month: string;
  mrr: number;
}

const defaultChartData: MRRBarListData[] = [
  { month: "January", mrr: 186 },
  { month: "February", mrr: 305 },
  { month: "March", mrr: 237 },
  { month: "April", mrr: 73 },
  { month: "May", mrr: 209 },
  { month: "June", mrr: 214 },
]

const chartConfig = {
  mrr: {
    label: "MRR",
    color: "hsl(var(--chart-1))",
  },
} satisfies ChartConfig

export function MRRBarListChart({
  mrrData = defaultChartData
}: {
  mrrData?: MRRBarListData[]
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Bar Chart</CardTitle>
        <CardDescription>January - June 2024</CardDescription>
      </CardHeader>
      <CardContent>
        <ChartContainer config={chartConfig}>
          <BarChart accessibilityLayer data={mrrData}>
            <CartesianGrid vertical={false} />
            <XAxis
              dataKey="month"
              tickLine={false}
              tickMargin={10}
              axisLine={false}
              tickFormatter={(value) => value.slice(0, 3)}
            />
            <ChartTooltip
              cursor={false}
              content={<ChartTooltipContent hideLabel />}
            />
            <Bar dataKey="mrr" fill="var(--color-mrr)" radius={8} />
          </BarChart>
        </ChartContainer>
      </CardContent>
      <CardFooter className="flex-col items-start gap-2 text-sm">
        <div className="flex gap-2 font-medium leading-none">
          Trending up by 5.2% this month <TrendingUp className="h-4 w-4" />
        </div>
        <div className="leading-none text-muted-foreground">
          Showing total visitors for the last 6 months
        </div>
      </CardFooter>
    </Card>
  )
}
