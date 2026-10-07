from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "TaskBoard API"
    app_version: str = "1.0.0"
    environment: str = "local"
    database_url: str = "postgresql+psycopg://taskboard:taskboard@localhost:5432/taskboard"
    # comma separated list; "*" only for local development
    cors_origins: str = "*"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
