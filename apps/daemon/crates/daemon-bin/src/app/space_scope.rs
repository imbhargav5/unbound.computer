use daemon_database::AsyncDatabase;
use rusqlite::{params, OptionalExtension};

const LOCAL_USER_ID: &str = "local-board";
const DEFAULT_MACHINE_NAME: &str = "This Device";
const DEFAULT_SPACE_NAME: &str = "Personal Space";
const DEFAULT_SPACE_COLOR: &str = "#3B82F6";

fn normalize_optional_id(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

pub async fn resolve_machine_space_scope(
    db: &AsyncDatabase,
    machine_id: Option<String>,
    requested_space_id: Option<String>,
) -> Result<(Option<String>, Option<String>), String> {
    let machine_id = normalize_optional_id(machine_id);
    let requested_space_id = normalize_optional_id(requested_space_id);

    let Some(machine_id_value) = machine_id.clone() else {
        return Ok((None, None));
    };

    let machine_id_for_db = machine_id_value.clone();
    let requested_space_id_for_db = requested_space_id.clone();

    let resolved_space_id = db
        .call_with_operation("space_scope.resolve", move |conn| {
            conn.execute(
                "INSERT OR IGNORE INTO machines (id, user_id, name) VALUES (?1, ?2, ?3)",
                params![machine_id_for_db, LOCAL_USER_ID, DEFAULT_MACHINE_NAME],
            )?;

            let mut resolved_space_id = requested_space_id_for_db;

            if let Some(space_id) = resolved_space_id.clone() {
                let existing_machine_id: Option<String> = conn
                    .query_row(
                        "SELECT machine_id FROM spaces WHERE id = ?1",
                        params![space_id.as_str()],
                        |row| row.get(0),
                    )
                    .optional()?;

                match existing_machine_id {
                    Some(existing_machine_id) if existing_machine_id == machine_id_for_db => {}
                    Some(_) => {
                        resolved_space_id = None;
                    }
                    None => {
                        conn.execute(
                            "INSERT INTO spaces (id, name, user_id, machine_id, color, created_at)
                             VALUES (?1, ?2, ?3, ?4, ?5, datetime('now'))",
                            params![
                                space_id.as_str(),
                                DEFAULT_SPACE_NAME,
                                LOCAL_USER_ID,
                                machine_id_for_db.as_str(),
                                DEFAULT_SPACE_COLOR,
                            ],
                        )?;
                    }
                }
            }

            if resolved_space_id.is_none() {
                resolved_space_id = conn
                    .query_row(
                        "SELECT id
                         FROM spaces
                         WHERE machine_id = ?1
                         ORDER BY datetime(created_at) ASC, id ASC
                         LIMIT 1",
                        params![machine_id_for_db.as_str()],
                        |row| row.get(0),
                    )
                    .optional()?;
            }

            if resolved_space_id.is_none() {
                let generated_space_id = format!("{machine_id_for_db}-personal-space");
                conn.execute(
                    "INSERT OR IGNORE INTO spaces (id, name, user_id, machine_id, color, created_at)
                     VALUES (?1, ?2, ?3, ?4, ?5, datetime('now'))",
                    params![
                        generated_space_id.as_str(),
                        DEFAULT_SPACE_NAME,
                        LOCAL_USER_ID,
                        machine_id_for_db.as_str(),
                        DEFAULT_SPACE_COLOR,
                    ],
                )?;
                resolved_space_id = Some(generated_space_id);
            }

            Ok(resolved_space_id)
        })
        .await
        .map_err(|error| error.to_string())?;

    Ok((Some(machine_id_value), resolved_space_id))
}
