import requests
import sys
import os
import argparse
from sentence_transformers.util import semantic_search
import torch

API_URL = "http://sauron:8000/v1/embeddings"
DEFAULT_BATCH_SIZE = 1  # Process one at a time due to very long log lines

def embed(texts, batch_size):
    """Embed texts in batches to avoid overwhelming the server."""
    if len(texts) <= batch_size:
        resp = requests.post(API_URL, json={'input': texts}).json()
        return [d['embedding'] for d in resp['data']]
    
    # Process in batches
    all_embeddings = []
    for i in range(0, len(texts), batch_size):
        batch = texts[i:i + batch_size]
        resp = requests.post(API_URL, json={'input': batch}).json()
        all_embeddings.extend([d['embedding'] for d in resp['data']])
    return all_embeddings

def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description='Semantic search over log lines')
    parser.add_argument('-s', '--batch-size', type=int, default=DEFAULT_BATCH_SIZE,
                        help=f'Number of lines to send at once to embedding server (default: {DEFAULT_BATCH_SIZE})')
    parser.add_argument('query', nargs='*', help='Query to search for (if not provided, enters interactive mode)')
    args = parser.parse_args()
    
    # Read log lines from stdin
    print("Reading log lines from stdin...", file=sys.stderr)
    texts = []
    for line in sys.stdin:
        line = line.strip()
        if line:  # Skip empty lines
            texts.append(line)
    
    if not texts:
        print("No input received. Please pipe data to stdin.", file=sys.stderr)
        sys.exit(1)
    
    print(f"Loaded {len(texts)} log lines.", file=sys.stderr)
    print("Generating embeddings...", file=sys.stderr)
    
    # Generate embeddings for all log lines
    output = embed(texts, args.batch_size)
    
    # Convert to PyTorch tensor for semantic search
    dataset_embeddings = torch.FloatTensor(output)
    
    # Check if query provided as command-line argument
    if args.query:
        query = ' '.join(args.query)
        print(f"Query: {query}", file=sys.stderr)
        
        # Embed the query
        query_output = embed([query], args.batch_size)
        query_embeddings = torch.FloatTensor(query_output)
        
        # Find top 5 most similar log lines
        hits = semantic_search(query_embeddings, dataset_embeddings, top_k=5)
        
        print("\nTop 5 matches:")
        for i, hit in enumerate(hits[0], 1):
            score = hit['score']
            idx = hit['corpus_id']
            print(f"{i}. [Score: {score:.4f}] {texts[idx]}")
        
        sys.exit(0)
    
    print("Ready for queries. Type your query (or 'quit' to exit):", file=sys.stderr)
    
    # Open terminal for interactive input (bypass the piped stdin)
    try:
        tty = open('/dev/tty', 'r')
    except OSError:
        print("Cannot open /dev/tty for interactive input. Running in non-interactive mode.", file=sys.stderr)
        sys.exit(0)
    
    # Interactive query loop
    while True:
        try:
            sys.stderr.write("\n> ")
            sys.stderr.flush()
            query = tty.readline().strip()
            
            if query.lower() in ['quit', 'exit', 'q']:
                print("Goodbye!", file=sys.stderr)
                break
            
            if not query:
                continue
            
            # Embed the query
            query_output = embed([query], args.batch_size)
            query_embeddings = torch.FloatTensor(query_output)
            
            # Find top 5 most similar log lines
            hits = semantic_search(query_embeddings, dataset_embeddings, top_k=5)
            
            print("\nTop 5 matches:")
            for i, hit in enumerate(hits[0], 1):
                score = hit['score']
                idx = hit['corpus_id']
                print(f"{i}. [Score: {score:.4f}] {texts[idx]}")
        
        except EOFError:
            print("\nGoodbye!", file=sys.stderr)
            break
        except KeyboardInterrupt:
            print("\nGoodbye!", file=sys.stderr)
            break
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
    
    tty.close()

if __name__ == "__main__":
    main()

