import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import Link from 'next/link';

type Props = {
  author: {
    avatar_url: string;
    bio: string;
    created_at: string;
    display_name: string;
    facebook_handle: string | null;
    instagram_handle: string | null;
    linkedin_handle: string | null;
    twitter_handle: string | null;
    updated_at: string;
    user_id: string;
    website_url: string | null;
  };
};

const AuthorCard = ({ author }: Props) => {
  return (
    <Link href={`/blog/authors/${author.user_id}`} key={author.user_id}>
      <Card>
        <CardHeader>
          <div className="flex">
            <Avatar>
              <AvatarImage src={author.avatar_url} />
              <AvatarFallback>
                {generateInitials(author.display_name)}
              </AvatarFallback>
            </Avatar>
            <div className="ml-4">
              <CardTitle>{author.display_name}</CardTitle>
              <CardDescription className="mt-2">
                {author.bio.length > 120
                  ? author.bio.slice(0, 120) + '...'
                  : author.bio.length}
              </CardDescription>
            </div>
          </div>
        </CardHeader>
      </Card>
    </Link>
  );
};

export default AuthorCard;

function generateInitials(name: string) {
  // Split the name into individual words
  const words = name.split(' ');

  // Initialize an empty string to store initials
  let initials = '';

  // Iterate through each word
  for (let i = 0; i < words.length; i++) {
    // Get the first character of each word and convert it to uppercase
    initials += words[i][0].toUpperCase();
  }

  // Return the generated initials
  return initials;
}
