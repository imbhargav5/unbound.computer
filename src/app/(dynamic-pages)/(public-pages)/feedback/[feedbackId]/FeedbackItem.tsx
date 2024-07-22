// components/FeedbackItem.tsx
import { T } from "@/components/ui/Typography"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardFooter, CardHeader } from "@/components/ui/card"
import { formatDistance } from 'date-fns'
import { Bug, LucideCloudLightning, MessageSquareDot } from "lucide-react"
import Link from 'next/link'

interface FeedbackType {
  id: string
  user_id: string
  title: string
  content: string
  type: 'bug' | 'feature_request' | 'general'
  created_at: string
}

interface FiltersSchema {
  page?: number
}

const typeIcons = {
  bug: <Bug className="h-4 w-4 mr-1 text-destructive" />,
  feature_request: <LucideCloudLightning className="h-4 w-4 mr-1 text-primary" />,
  general: <MessageSquareDot className="h-4 w-4 mr-1 text-secondary" />,
}

const TAGS = {
  bug: 'Bug',
  feature_request: 'Feature Request',
  general: 'General',
}

interface FeedbackItemProps {
  feedback: FeedbackType
  filters: FiltersSchema
  feedbackId?: string
}

export function FeedbackItem({ feedback, filters, feedbackId }: FeedbackItemProps) {
  const searchParams = new URLSearchParams()

  if (filters.page) searchParams.append('page', filters.page.toString())

  const href = `/feedback/${feedback.id}?${searchParams.toString()}`

  return (
    <Link href={href}>
      <Card
        data-testid="feedback-item"
        data-feedback={feedbackId === feedback.id}
        className="hover:bg-muted transition-colors duration-200 ease-in cursor-pointer group"
      >
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <Avatar className="h-8 w-8">
            <AvatarImage src={`https://avatar.vercel.sh/${feedback.user_id}`} alt="User avatar" />
            <AvatarFallback>U</AvatarFallback>
          </Avatar>
          <T.Small className="text-muted-foreground">
            {formatDistance(new Date(feedback.created_at), new Date(), { addSuffix: true })}
          </T.Small>
        </CardHeader>
        <CardContent>
          <T.H3>{feedback.title}</T.H3>
          <T.P className="text-muted-foreground line-clamp-2">{feedback.content}</T.P>
        </CardContent>
        <CardFooter>
          <Badge variant="secondary" className="rounded-full group-hover:bg-background">
            {typeIcons[feedback.type]} {TAGS[feedback.type]}
          </Badge>
        </CardFooter>
      </Card>
    </Link>
  )
}
