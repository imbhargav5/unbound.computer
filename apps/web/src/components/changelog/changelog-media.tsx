export type ChangelogMediaType = "image" | "video" | "gif";

type ChangelogMediaProps = {
  type: ChangelogMediaType;
  src: string;
  alt?: string | null;
  poster?: string | null;
  className?: string;
};

export function ChangelogMedia({
  type,
  src,
  alt,
  poster,
  className,
}: ChangelogMediaProps) {
  if (type === "video") {
    return (
      <video
        className={className}
        controls
        muted
        playsInline
        poster={poster ?? undefined}
      >
        <source src={src} />
      </video>
    );
  }

  return (
    <img
      className={className}
      src={src}
      alt={alt ?? "Changelog media"}
      loading="lazy"
    />
  );
}
