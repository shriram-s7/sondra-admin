import os
import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import RedirectResponse, JSONResponse, FileResponse
from fastapi.exceptions import HTTPException, RequestValidationError
from database import engine
import models
from routers import auth, songs, playlists, stream, sync, history

from dotenv import load_dotenv
load_dotenv(override=True)

# Create database tables if they do not exist
models.Base.metadata.create_all(bind=engine)

# Periodic Sync Daemon task definition
async def run_periodic_sync_daemon():
    # Allow uvicorn to fully bind ports before the first immediate sync trigger
    await asyncio.sleep(1)
    print("Sync Daemon: Triggering immediate startup library sync...")
    
    root_id = os.getenv("GDRIVE_ROOT_FOLDER_ID")
    from routers.sync import sync_manager, execute_sync_and_broadcast
    
    if root_id:
        try:
            await execute_sync_and_broadcast()
        except Exception as e:
            print(f"Sync Daemon Startup Sync Error: {e}")
    else:
        print("Sync Daemon: GDRIVE_ROOT_FOLDER_ID is not configured. Skipping startup sync.")
        
    while True:
        try:
            from dotenv import load_dotenv
            load_dotenv(override=True)
            
            interval_str = os.getenv("SYNC_INTERVAL_SECONDS", "900")
            interval = int(interval_str)
        except Exception:
            interval = 900

        await asyncio.sleep(interval)
        
        if not sync_manager.is_syncing and os.getenv("GDRIVE_ROOT_FOLDER_ID"):
            print("Sync Daemon: Triggering periodic background sync...")
            try:
                await execute_sync_and_broadcast()
            except Exception as e:
                print(f"Sync Daemon Error during sync: {e}")
        else:
            if not os.getenv("GDRIVE_ROOT_FOLDER_ID"):
                print("Sync Daemon: GDRIVE_ROOT_FOLDER_ID is not configured. Skipping sync.")

# FastAPI Lifespan manager
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup actions
    sync_task = asyncio.create_task(run_periodic_sync_daemon())
    yield
    # Shutdown actions
    print("Sondra shutting down. Cancelling background tasks...")
    sync_task.cancel()
    try:
        await sync_task
    except asyncio.CancelledError:
        pass

# Initialize FastAPI app with lifespan context
app = FastAPI(
    title="Sondra Music Platform",
    description="Personal music streaming platform using Google Drive backend.",
    version="1.0.0",
    lifespan=lifespan
)

# Custom Global Error Handler Overrides
@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    """Format HTTP exceptions into consistent JSON error format."""
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": exc.detail},
        headers=exc.headers
    )

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Format request validation exceptions into consistent JSON error format."""
    errors = exc.errors()
    if errors:
        first_err = errors[0]
        field_loc = ".".join(str(x) for x in first_err.get("loc", []))
        message = f"{first_err.get('msg', 'Validation error')} for field: {field_loc}"
    else:
        message = "Request validation failed"
        
    return JSONResponse(
        status_code=422,
        content={"error": message}
    )

# Configure CORS
cors_origins_str = os.getenv("CORS_ORIGINS", "")
if cors_origins_str:
    origins = [o.strip() for o in cors_origins_str.split(",") if o.strip()]
else:
    origins = [
        "http://localhost:5173",
        "http://127.0.0.1:5173",
        "http://localhost:8000",
        "http://127.0.0.1:8000",
    ]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins if origins else ["*"],
    allow_credentials=True if origins else False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register routers under standard routes and /api prefix
app.include_router(auth.router)
app.include_router(auth.router, prefix="/api")
app.include_router(songs.router, prefix="/api")
app.include_router(playlists.router, prefix="/api")
app.include_router(stream.router, prefix="/api")
app.include_router(sync.router, prefix="/api")
app.include_router(history.router)
app.include_router(history.router, prefix="/api")

@app.get("/events")
async def root_sse_events(request: Request):
    from routers.sync import sse_events_endpoint
    return await sse_events_endpoint(request)

@app.get("/api/events")
async def api_sse_events(request: Request):
    from routers.sync import sse_events_endpoint
    return await sse_events_endpoint(request)

@app.api_route("/health", methods=["GET", "HEAD"])
async def health():
    """Health check endpoint supporting GET and HEAD requests."""
    return {"status": "ok"}

@app.get("/")
def read_root():
    """API Root status endpoint."""
    return {"message": "Sondra Music Platform API", "status": "active"}
