'use client';

import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuPortal,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import type { UserRole } from '@/types/userTypes';
import {
  NEW_PRIORITY_OPTIONS,
  NEW_STATUS_OPTIONS,
  NEW_TYPE_OPTIONS,
} from '@/utils/feedback';
import { DotsVerticalIcon } from '@radix-ui/react-icons';
import {
  ArrowDown,
  ArrowUpRight,
  EyeIcon,
  EyeOffIcon,
  MessageSquare,
  MessageSquareOff,
  Tags,
  VolumeX,
} from 'lucide-react';

import {
  adminToggleFeedbackFromRoadmapAction,
  adminToggleFeedbackOpenForCommentsAction,
  adminToggleFeedbackVisibilityAction,
  adminUpdateFeedbackPriority,
  adminUpdateFeedbackStatusAction,
  adminUpdateFeedbackTypeAction,
} from '@/data/feedback';
import { useSAToastMutation } from '@/hooks/useSAToastMutation';
import type { Tables } from '@/lib/database.types';
import type { DBTable } from '@/types';
import { userRoles } from '@/utils/userTypes';

function FeedbackActionsDropdown({
  feedback,
  userRole,
}: {
  feedback: DBTable<'internal_feedback_threads'>;
  userRole: UserRole;
}) {
  if (userRole === userRoles.ANON) {
    return null;
  }

  const updateFeedbackStatus = useSAToastMutation(
    async ({
      feedbackId,
      status,
    }: {
      feedbackId: string;
      status: Tables<'internal_feedback_threads'>['status'];
    }) => {
      return await adminUpdateFeedbackStatusAction({ feedbackId, status })
    },
    {
      loadingMessage(variables) {
        return `Updating status to ${variables.status}`;
      },
      successMessage(data, variables) {
        return `Status has been updated to ${variables.status}`;
      },
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to update status ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to update status';
        }
      },
    },
  );

  const updateFeedbackType = useSAToastMutation(
    async ({
      feedbackId,
      type,
    }: {
      feedbackId: string;
      type: Tables<'internal_feedback_threads'>['type'];
    }) => {
      return await adminUpdateFeedbackTypeAction({ feedbackId, type });
    },
    {
      loadingMessage(variables) {
        return `Updating type to ${variables.type}`;
      },
      successMessage(data, variables) {
        return `Type has been updated to ${variables.type}`;
      },
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to update type ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to update type';
        }
      },
    },
  );

  const updateFeedbackPriority = useSAToastMutation(
    async ({
      feedbackId,
      priority,
    }: {
      feedbackId: string;
      priority: Tables<'internal_feedback_threads'>['priority'];
    }) => {
      return await adminUpdateFeedbackPriority({ feedbackId, priority });
    },
    {
      loadingMessage(variables) {
        return `Updating priority to ${variables.priority}`;
      },
      successMessage(data, variables) {
        return `Priority has been updated to ${variables.priority}`;
      },
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to update priority ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to update priority';
        }
      },
    },
  );

  const updateRoadmap = useSAToastMutation(
    async ({
      feedbackId,
      isInRoadmap,
    }: {
      feedbackId: string;
      isInRoadmap: boolean;
    }) => {
      return await adminToggleFeedbackFromRoadmapAction({
        feedbackId,
        isInRoadmap,
      });
    },
    {
      loadingMessage(variables) {
        return variables.isInRoadmap
          ? 'Adding to roadmap'
          : 'Removing from roadmap';
      },
      successMessage(data, variables) {
        return variables.isInRoadmap
          ? 'Added to roadmap'
          : 'Removed from roadmap';
      },
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to update priority ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to update priority';
        }
      },
    },
  );

  const updateOpenForComments = useSAToastMutation(
    async ({
      feedbackId,
      isOpenForComments,
    }: {
      feedbackId: string;
      isOpenForComments: boolean;
    }) => {
      return await adminToggleFeedbackOpenForCommentsAction({
        feedbackId,
        isOpenForComments,
      });
    },
    {
      loadingMessage(variables) {
        return variables.isOpenForComments
          ? 'Opening thread for comments'
          : 'Closing thread for comments';
      },
      successMessage(data, variables) {
        return variables.isOpenForComments
          ? 'Thread is now open for comments'
          : 'Thread is now closed for comments';
      },
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to update open for comments ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to update open for comments';
        }
      },
    },
  );

  const updateVisibility = useSAToastMutation(
    async ({
      feedbackId,
      isPubliclyVisible,
    }: {
      feedbackId: string;
      isPubliclyVisible: boolean;
    }) => {
      return await adminToggleFeedbackVisibilityAction({
        feedbackId,
        isPubliclyVisible,
      });
    },
    {
      loadingMessage(variables) {
        return variables.isPubliclyVisible
          ? 'Showing thread from public'
          : 'Hiding thread to public';
      },
      errorMessage(error, variables) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to update visibility ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to update visibility';
        }
      },
      successMessage(data, variables) {
        return variables.isPubliclyVisible
          ? 'Thread is now publicly visible'
          : 'Thread is now hidden from public';
      },
    },
  );

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon">
          <DotsVerticalIcon data-testid="feedback-actions-dropdown-button" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent className="w-56">
        {userRole === userRoles.ADMIN && (
          <>
            <DropdownMenuLabel>Manage Filters</DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuGroup>
              <DropdownMenuSub>
                <DropdownMenuSubTrigger>
                  <Tags className="h-4 w-4 mr-2" />
                  Apply status
                </DropdownMenuSubTrigger>
                <DropdownMenuPortal>
                  <DropdownMenuSubContent>
                    {NEW_STATUS_OPTIONS?.map((status) => (
                      <DropdownMenuItem
                        key={status.label}
                        onClick={async () => {
                          updateFeedbackStatus.mutate({
                            feedbackId: feedback.id,
                            status: status.value,
                          });
                        }}
                      >
                        <status.icon className="h-4 w-4 mr-2" /> {status.label}
                      </DropdownMenuItem>
                    ))}
                  </DropdownMenuSubContent>
                </DropdownMenuPortal>
              </DropdownMenuSub>
              <DropdownMenuSub>
                <DropdownMenuSubTrigger>
                  <Tags className="h-4 w-4 mr-2" />
                  Apply type
                </DropdownMenuSubTrigger>
                <DropdownMenuPortal>
                  <DropdownMenuSubContent>
                    {NEW_TYPE_OPTIONS?.map((type) => (
                      <DropdownMenuItem
                        key={type.label}
                        onClick={async () => {
                          updateFeedbackType.mutate({
                            feedbackId: feedback.id,
                            type: type.value,
                          });
                        }}
                      >
                        <type.icon className="h-4 w-4 mr-2" /> {type.label}
                      </DropdownMenuItem>
                    ))}
                  </DropdownMenuSubContent>
                </DropdownMenuPortal>
              </DropdownMenuSub>
              <DropdownMenuSub>
                <DropdownMenuSubTrigger>
                  <Tags className="h-4 w-4 mr-2" />
                  Apply priority
                </DropdownMenuSubTrigger>
                <DropdownMenuPortal>
                  <DropdownMenuSubContent>
                    {NEW_PRIORITY_OPTIONS?.map((priority) => (
                      <DropdownMenuItem
                        key={priority.label}
                        onClick={async () => {
                          updateFeedbackPriority.mutate({
                            feedbackId: feedback.id,
                            priority: priority.value,
                          });
                        }}
                      >
                        <priority.icon className="h-4 w-4 mr-2" />{' '}
                        {priority.label}
                      </DropdownMenuItem>
                    ))}
                  </DropdownMenuSubContent>
                </DropdownMenuPortal>
              </DropdownMenuSub>
            </DropdownMenuGroup>
            <DropdownMenuSeparator />
          </>
        )}
        {(userRole === userRoles.ADMIN || userRole === userRoles.USER) && (
          <>
            <DropdownMenuLabel>Thread Settings</DropdownMenuLabel>
            <DropdownMenuGroup>
              <DropdownMenuItem>
                <VolumeX className="h-4 w-4 mr-2" /> Mute this thread
              </DropdownMenuItem>
            </DropdownMenuGroup>
          </>
        )}
        {userRole === userRoles.ADMIN && (
          <>
            <DropdownMenuSeparator />
            <DropdownMenuLabel>Admin Settings</DropdownMenuLabel>
            <DropdownMenuItem
              onClick={async () => {
                updateRoadmap.mutate({
                  feedbackId: feedback.id,
                  isInRoadmap: !feedback?.added_to_roadmap,
                });
              }}
            >
              {feedback?.added_to_roadmap ? (
                <>
                  <ArrowDown className="h-4 w-4 mr-2" />
                  Remove from roadmap
                </>
              ) : (
                <>
                  <ArrowUpRight className="h-4 w-4 mr-2" />
                  Add to roadmap
                </>
              )}
            </DropdownMenuItem>
            <DropdownMenuItem
              onClick={async () => {
                updateOpenForComments.mutate({
                  feedbackId: feedback.id,
                  isOpenForComments: !feedback?.open_for_public_discussion,
                });
              }}
            >
              {feedback?.open_for_public_discussion ? (
                <>
                  <MessageSquareOff className="h-4 w-4 mr-2" /> Close for
                  comments
                </>
              ) : (
                <>
                  <MessageSquare
                    className="h-4 w-4 mr-2"
                    data-testid="open-for-comments-button"
                  />
                  Open for comments
                </>
              )}
            </DropdownMenuItem>
            <DropdownMenuItem
              onClick={async () => {
                updateVisibility.mutate({
                  feedbackId: feedback.id,
                  isPubliclyVisible: !feedback?.is_publicly_visible,
                });
              }}
            >
              {feedback?.is_publicly_visible ? (
                <>
                  <EyeOffIcon className="h-4 w-4 mr-2" /> Make this thread
                  private
                </>
              ) : (
                <>
                  <EyeIcon
                    className="h-4 w-4 mr-2"
                    data-testid="show-thread-button"
                  />{' '}
                  Make this thread public
                </>
              )}
            </DropdownMenuItem>
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

export default FeedbackActionsDropdown;
