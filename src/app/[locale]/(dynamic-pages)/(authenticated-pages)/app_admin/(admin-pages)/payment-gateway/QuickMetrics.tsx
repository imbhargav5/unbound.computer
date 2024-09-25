import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Typography } from "@/components/ui/Typography"
import { Activity, CreditCard, DollarSign, Users } from "lucide-react"

interface MetricCardProps {
  title: string
  value: string
  change: string
  icon: React.ReactNode
}

function MetricCard({ title, value, change, icon }: MetricCardProps) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
        {icon}
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-bold">{value}</div>
        <p className="text-xs text-muted-foreground">{change}</p>
      </CardContent>
    </Card>
  )
}

export function QuickMetrics() {
  return (
    <div className="space-y-4">
      <Typography.H4>Quick Metrics</Typography.H4>
      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-4">
        <MetricCard
          title="Total Revenue"
          value="$45,231.89"
          change="+20.1% from last month"
          icon={<DollarSign className="h-4 w-4 text-muted-foreground" />}
        />
        <MetricCard
          title="Subscriptions"
          value="+2350"
          change="+180.1% from last month"
          icon={<Users className="h-4 w-4 text-muted-foreground" />}
        />
        <MetricCard
          title="Sales"
          value="+12,234"
          change="+19% from last month"
          icon={<CreditCard className="h-4 w-4 text-muted-foreground" />}
        />
        <MetricCard
          title="Active Now"
          value="+573"
          change="+201 since last hour"
          icon={<Activity className="h-4 w-4 text-muted-foreground" />}
        />
      </div>
    </div>
  )
}
